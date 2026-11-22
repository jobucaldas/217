package reminder

import (
	"encoding/json"
	"errors"
	"sync/atomic"
	"testing"
	"testing/synctest"
	"time"

	"217/backend/internal/model"
	"217/backend/internal/store"
)

type fakeSender struct {
	calls     int32
	fail      bool
	failures  int32
	permanent bool
	payload   map[string]string
}

func (s *fakeSender) Send(_ model.ReminderTarget, payload []byte) (bool, error) {
	calls := atomic.AddInt32(&s.calls, 1)
	_ = json.Unmarshal(payload, &s.payload)
	if s.fail || calls <= s.failures {
		return s.permanent, errors.New("send failure")
	}
	return false, nil
}

func reminderStore(t *testing.T, reminderTime string) *store.MemoryStore {
	t.Helper()
	s := store.NewMemoryStore()
	user, err := s.CreateUser("reminder@example.com", "Reminder", "password")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.RecordConsent(user.ID, model.ConsentVersion); err != nil {
		t.Fatal(err)
	}
	request := model.PushSubscriptionRequest{Endpoint: "https://push.example/one"}
	request.Keys.P256DH = "p256dh"
	request.Keys.Auth = "auth"
	if _, err := s.SavePushSubscription(user.ID, request); err != nil {
		t.Fatal(err)
	}
	_, err = s.UpsertReminderPreference(user.ID, model.ReminderPreference{
		Enabled: true, Time: reminderTime, Timezone: "America/Sao_Paulo",
	})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestIsDueUsesConfiguredTimezone(t *testing.T) {
	// 23:15 UTC is 20:15 in Sao Paulo.
	now := time.Date(2026, 5, 13, 23, 15, 0, 0, time.UTC)
	date, due := IsDue(now, "20:00", "America/Sao_Paulo")
	if !due || date.Format("2006-01-02") != "2026-05-13" {
		t.Fatalf("expected reminder to be due on local date, got due=%v date=%v", due, date)
	}
	if _, due := IsDue(now, "20:30", "America/Sao_Paulo"); due {
		t.Fatal("reminder must not be due before the configured local time")
	}
	if _, due := IsDue(now, "20:00", "Not/AZone"); due {
		t.Fatal("invalid timezone must never be due")
	}
}

func TestRunOnceSendsDueReminderOnlyOnce(t *testing.T) {
	s := reminderStore(t, "20:00")
	sender := &fakeSender{}
	now := time.Date(2026, 5, 13, 23, 15, 0, 0, time.UTC)
	service := Service{Store: s, Sender: sender, Now: func() time.Time { return now }}
	if err := service.RunOnce(); err != nil {
		t.Fatal(err)
	}
	if err := service.RunOnce(); err != nil {
		t.Fatal(err)
	}
	if sender.calls != 1 {
		t.Fatalf("expected duplicate protection to send once, got %d", sender.calls)
	}
	if sender.payload["date"] != "2026-05-13" || sender.payload["tag"] != "217-reminder-2026-05-13" {
		t.Fatalf("payload lacks stable local-day identity: %#v", sender.payload)
	}
}

func TestRunOnceBacksOffAndRecoversStaleClaim(t *testing.T) {
	s := reminderStore(t, "20:00")
	sender := &fakeSender{fail: true}
	now := time.Date(2026, 5, 13, 23, 15, 0, 0, time.UTC)
	service := Service{Store: s, Sender: sender, Now: func() time.Time { return now }}
	_ = service.RunOnce()
	_ = service.RunOnce()
	if sender.calls != 1 {
		t.Fatalf("failure must be backed off, got %d immediate attempts", sender.calls)
	}
	now = now.Add(59 * time.Second)
	_ = service.RunOnce()
	if sender.calls != 1 {
		t.Fatal("retry happened before one-minute backoff")
	}
	now = now.Add(time.Second)
	sender.fail = false
	_ = service.RunOnce()
	if sender.calls != 2 {
		t.Fatalf("expected retry after backoff, got %d", sender.calls)
	}

	// A worker crash leaves a claim; it is reclaimable only after the five-minute lease.
	s2 := reminderStore(t, "20:00")
	targets, _ := s2.ListReminderTargets()
	date, _ := IsDue(now, "20:00", "America/Sao_Paulo")
	claimed, _, _ := s2.ClaimReminderDelivery(targets[0], date, now)
	if !claimed {
		t.Fatal("initial claim failed")
	}
	claimed, _, _ = s2.ClaimReminderDelivery(targets[0], date, now.Add(4*time.Minute))
	if claimed {
		t.Fatal("active lease was stolen")
	}
	claimed, _, _ = s2.ClaimReminderDelivery(targets[0], date, now.Add(5*time.Minute))
	if !claimed {
		t.Fatal("stale claim was not recovered")
	}
}

func TestPermanentFailureDeletesSubscription(t *testing.T) {
	s := reminderStore(t, "20:00")
	sender := &fakeSender{fail: true, permanent: true}
	service := Service{Store: s, Sender: sender, Now: func() time.Time {
		return time.Date(2026, 5, 13, 23, 15, 0, 0, time.UTC)
	}}
	_ = service.RunOnce()
	targets, _ := s.ListReminderTargets()
	if len(targets) != 0 {
		t.Fatalf("expired subscription was not removed: %#v", targets)
	}
}

type schedulerStore struct {
	*store.MemoryStore
	listTimes []time.Time
	claims    atomic.Int32
	failLists int
}

func (s *schedulerStore) ListReminderTargets() ([]model.ReminderTarget, error) {
	s.listTimes = append(s.listTimes, time.Now())
	if len(s.listTimes) <= s.failLists {
		return nil, errors.New("temporary database error")
	}
	return s.MemoryStore.ListReminderTargets()
}

func (s *schedulerStore) ClaimReminderDelivery(target model.ReminderTarget, day, now time.Time) (bool, time.Time, error) {
	s.claims.Add(1)
	return s.MemoryStore.ClaimReminderDelivery(target, day, now)
}

func (s *fakeSender) callCount() int32 { return atomic.LoadInt32(&s.calls) }

func startScheduler(s *Service) func() {
	stop, done := make(chan struct{}), make(chan struct{})
	go func() {
		defer close(done)
		s.Run(stop)
	}()
	synctest.Wait()
	return func() {
		close(stop)
		<-done
	}
}

func advanceScheduler(d time.Duration) {
	time.Sleep(d)
	synctest.Wait()
}

func schedulerClock() func() time.Time {
	start := time.Now()
	due := time.Date(2026, 5, 13, 23, 0, 0, 0, time.UTC)
	return func() time.Time { return due.Add(time.Since(start)) }
}

func TestSchedulerIdleAndNotify(t *testing.T) {
	ms := reminderStore(t, "20:00")
	targets, _ := ms.ListReminderTargets()
	pref := model.ReminderPreference{Time: "20:00", Timezone: targets[0].Timezone}
	if _, err := ms.UpsertReminderPreference(targets[0].UserID, pref); err != nil {
		t.Fatal(err)
	}
	synctest.Test(t, func(t *testing.T) {
		s := &schedulerStore{MemoryStore: ms}
		sender := &fakeSender{}
		service := &Service{Store: s, Sender: sender, Now: schedulerClock()}
		defer startScheduler(service)() // Stop with tomorrow's timer armed.
		advanceScheduler(24 * time.Hour)
		if len(s.listTimes) != 1 || s.claims.Load() != 0 {
			t.Fatalf("idle scheduler queried the store: %d reloads, %d claims", len(s.listTimes), s.claims.Load())
		}

		pref.Enabled, pref.Time = true, "20:10"
		if _, err := ms.UpsertReminderPreference(targets[0].UserID, pref); err != nil {
			t.Fatal(err)
		}
		service.Notify()
		synctest.Wait()
		if len(s.listTimes) != 2 || s.claims.Load() != 0 {
			t.Fatalf("new target wasn't scheduled for later: %d reloads, %d claims", len(s.listTimes), s.claims.Load())
		}
		pref.Time = "20:00"
		if _, err := ms.UpsertReminderPreference(targets[0].UserID, pref); err != nil {
			t.Fatal(err)
		}
		service.Notify()
		synctest.Wait()
		if len(s.listTimes) != 3 || sender.callCount() != 1 {
			t.Fatalf("time change did not deliver immediately: %d reloads, %d sends", len(s.listTimes), sender.callCount())
		}
	})
}

func TestSchedulerRetriesAtPersistedBackoffThenTomorrow(t *testing.T) {
	ms := reminderStore(t, "20:00")
	synctest.Test(t, func(t *testing.T) {
		backoffs := []time.Duration{1, 2, 4, 8, 16, 32, 32}
		s := &schedulerStore{MemoryStore: ms}
		sender := &fakeSender{failures: int32(len(backoffs))}
		service := &Service{Store: s, Sender: sender, Now: schedulerClock()}
		defer startScheduler(service)()
		var elapsed time.Duration
		for i, minutes := range backoffs {
			delay := minutes * time.Minute
			advanceScheduler(delay - time.Nanosecond)
			if s.claims.Load() != int32(i+1) || sender.callCount() != int32(i+1) {
				t.Fatalf("attempt %d retried early: %d claims, %d sends", i+1, s.claims.Load(), sender.callCount())
			}
			advanceScheduler(time.Nanosecond)
			if sender.callCount() != int32(i+2) {
				t.Fatalf("attempt %d not retried at %v: %d sends", i+1, delay, sender.callCount())
			}
			elapsed += delay
		}
		advanceScheduler(24*time.Hour - elapsed - time.Nanosecond)
		if sender.callCount() != sender.failures+1 {
			t.Fatal("successful send was repeated on the same day")
		}
		advanceScheduler(time.Nanosecond)
		if sender.callCount() != sender.failures+2 || len(s.listTimes) != 1 {
			t.Fatalf("next day: %d sends, %d reloads", sender.callCount(), len(s.listTimes))
		}
	})
}

func TestSchedulerRecoversPersistedLease(t *testing.T) {
	ms := reminderStore(t, "20:00")
	targets, _ := ms.ListReminderTargets()
	synctest.Test(t, func(t *testing.T) {
		clock := schedulerClock()
		now := clock()
		day, _ := IsDue(now, targets[0].Time, targets[0].Timezone)
		if claimed, _, err := ms.ClaimReminderDelivery(targets[0], day, now.Add(-3*time.Minute)); err != nil || !claimed {
			t.Fatalf("seed claim: %v, %v", claimed, err)
		}
		s := &schedulerStore{MemoryStore: ms}
		sender := &fakeSender{}
		defer startScheduler(&Service{Store: s, Sender: sender, Now: clock})()
		advanceScheduler(2*time.Minute - time.Nanosecond)
		if sender.callCount() != 0 || s.claims.Load() != 1 {
			t.Fatal("checked again before the outstanding lease ended")
		}
		advanceScheduler(time.Nanosecond)
		if sender.callCount() != 1 || s.claims.Load() != 2 {
			t.Fatal("did not recover the claim exactly at lease expiry")
		}
	})
}

func TestSchedulerDropsPermanentFailure(t *testing.T) {
	ms := reminderStore(t, "20:00")
	synctest.Test(t, func(t *testing.T) {
		s := &schedulerStore{MemoryStore: ms}
		sender := &fakeSender{failures: 1, permanent: true}
		defer startScheduler(&Service{Store: s, Sender: sender, Now: schedulerClock()})()
		advanceScheduler(48 * time.Hour)
		targets, _ := ms.ListReminderTargets()
		if s.claims.Load() != 1 || len(s.listTimes) != 1 || len(targets) != 0 {
			t.Fatalf("permanent failure left scheduled work: %d claims, %d reloads, %d targets", s.claims.Load(), len(s.listTimes), len(targets))
		}
	})
}

func TestSchedulerReloadBacksOffAndNotifyResets(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		start := time.Now()
		s := &schedulerStore{MemoryStore: store.NewMemoryStore(), failLists: 4}
		service := &Service{Store: s}
		defer startScheduler(service)()
		advanceScheduler(16 * time.Second)
		if len(s.listTimes) != 3 {
			t.Fatalf("expected three reloads before Notify, got %d", len(s.listTimes))
		}
		service.Notify()
		advanceScheduler(time.Hour)
		want := []int{0, 5, 15, 16, 21}
		if len(s.listTimes) != len(want) {
			t.Fatalf("got %d reloads, want %d", len(s.listTimes), len(want))
		}
		for i, seconds := range want {
			if got := s.listTimes[i].Sub(start); got != time.Duration(seconds)*time.Second {
				t.Errorf("reload %d at %v, want %ds", i, got, seconds)
			}
		}
	})
}

func TestReminderTomorrowAcrossDST(t *testing.T) {
	for _, tc := range []struct {
		name, zone, clock, today, want string
	}{
		{"spring gap", "America/New_York", "02:30", "2026-03-07T15:00:00Z", "2026-03-08T07:00:00Z"},
		{"spring normal", "America/New_York", "20:00", "2026-03-07T15:00:00Z", "2026-03-09T00:00:00Z"},
		{"fall overlap", "Europe/Berlin", "02:30", "2026-10-24T15:00:00Z", "2026-10-25T00:30:00Z"},
		{"fall normal", "Europe/Berlin", "20:00", "2026-10-24T15:00:00Z", "2026-10-25T19:00:00Z"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r, ok := parseReminderTime(tc.clock, tc.zone)
			if !ok {
				t.Fatal("invalid test reminder")
			}
			today, _ := time.Parse(time.RFC3339, tc.today)
			got := r.fire(r.day(today, 1))
			if got.UTC().Format(time.RFC3339) != tc.want {
				t.Fatalf("tomorrow fires at %v, want %v", got.UTC(), tc.want)
			}
			if _, due := IsDue(got.Add(-time.Nanosecond), tc.clock, tc.zone); due {
				t.Fatal("reminder was due before the selected instant")
			}
			if _, due := IsDue(got, tc.clock, tc.zone); !due {
				t.Fatal("reminder was not due at the selected instant")
			}
		})
	}
}
