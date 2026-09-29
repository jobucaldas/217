package reminder

import (
	"encoding/json"
	"errors"
	"testing"
	"time"

	"217/backend/internal/model"
	"217/backend/internal/store"
)

type fakeSender struct {
	calls     int
	fail      bool
	permanent bool
	payload   map[string]string
}

func (s *fakeSender) Send(_ model.ReminderTarget, payload []byte) (bool, error) {
	s.calls++
	_ = json.Unmarshal(payload, &s.payload)
	if s.fail {
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
	claimed, _ := s2.ClaimReminderDelivery(targets[0].SubscriptionID, date, now)
	if !claimed {
		t.Fatal("initial claim failed")
	}
	claimed, _ = s2.ClaimReminderDelivery(targets[0].SubscriptionID, date, now.Add(4*time.Minute))
	if claimed {
		t.Fatal("active lease was stolen")
	}
	claimed, _ = s2.ClaimReminderDelivery(targets[0].SubscriptionID, date, now.Add(5*time.Minute))
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
