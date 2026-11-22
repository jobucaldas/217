package reminder

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"
	"time"
	_ "time/tzdata" // The production image does not ship IANA timezone data.

	"217/backend/internal/model"
	"217/backend/internal/store"
	webpush "github.com/SherClockHolmes/webpush-go"
)

type Sender interface {
	Send(target model.ReminderTarget, payload []byte) (permanentFailure bool, err error)
}

type WebPushSender struct {
	PublicKey  string
	PrivateKey string
	Subject    string
	Client     *http.Client
}

func publicDialContext(ctx context.Context, network, address string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	addresses, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, err
	}
	dialer := net.Dialer{Timeout: 10 * time.Second}
	for _, address := range addresses {
		ip := address.IP
		if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() || ip.IsMulticast() {
			continue
		}
		if conn, dialErr := dialer.DialContext(ctx, network, net.JoinHostPort(ip.String(), port)); dialErr == nil {
			return conn, nil
		}
	}
	return nil, fmt.Errorf("push endpoint did not resolve to a public address")
}

func safePushClient() *http.Client {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	transport.DialContext = publicDialContext
	return &http.Client{
		Timeout:   15 * time.Second,
		Transport: transport,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
}

func (s WebPushSender) Send(target model.ReminderTarget, payload []byte) (bool, error) {
	client := s.Client
	if client == nil {
		client = safePushClient()
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	response, err := webpush.SendNotificationWithContext(ctx, payload, &webpush.Subscription{
		Endpoint: target.Endpoint,
		Keys:     webpush.Keys{P256dh: target.P256DH, Auth: target.Auth},
	}, &webpush.Options{HTTPClient: client, Subscriber: s.Subject, VAPIDPublicKey: s.PublicKey, VAPIDPrivateKey: s.PrivateKey, TTL: 3600, Topic: "daily-reminder"})
	if err != nil {
		return false, err
	}
	defer response.Body.Close()
	if response.StatusCode >= 200 && response.StatusCode < 300 {
		return false, nil
	}
	permanent := response.StatusCode == http.StatusGone || response.StatusCode == http.StatusNotFound
	return permanent, fmt.Errorf("push service returned %s", response.Status)
}

type Service struct {
	Store  store.Store
	Sender Sender
	Now    func() time.Time

	notifyOnce sync.Once
	changed    chan struct{}
}

func (s *Service) notifications() chan struct{} {
	s.notifyOnce.Do(func() { s.changed = make(chan struct{}, 1) })
	return s.changed
}

// Notify coalesces mutations without blocking the request that made them.
func (s *Service) Notify() {
	select {
	case s.notifications() <- struct{}{}:
	default:
	}
}

type reminderTime struct {
	location     *time.Location
	hour, minute int
}

func parseReminderTime(clock, timezone string) (reminderTime, bool) {
	location, err := time.LoadLocation(timezone)
	if err != nil {
		return reminderTime{}, false
	}
	parsed, err := time.Parse("15:04", clock)
	if err != nil {
		return reminderTime{}, false
	}
	return reminderTime{location, parsed.Hour(), parsed.Minute()}, true
}

func (r reminderTime) day(now time.Time, daysAhead int) time.Time {
	local := now.In(r.location)
	// This is a civil date key, not a local midnight (which can be skipped).
	return time.Date(local.Year(), local.Month(), local.Day()+daysAhead, 0, 0, 0, 0, time.UTC)
}

func (r reminderTime) fire(day time.Time) time.Time {
	fire := time.Date(day.Year(), day.Month(), day.Day(), r.hour, r.minute, 0, 0, r.location)
	start, end := fire.ZoneBounds()
	wall := day.Add(time.Duration(r.hour)*time.Hour + time.Duration(r.minute)*time.Minute)
	for _, transition := range []time.Time{start, end} {
		if transition.IsZero() {
			continue
		}
		_, before := transition.Add(-time.Nanosecond).Zone()
		_, after := transition.Zone()
		oldTime := wall.Add(-time.Duration(before) * time.Second)
		newTime := wall.Add(-time.Duration(after) * time.Second)
		if !oldTime.Before(transition) && newTime.Before(transition) {
			return transition // Spring gap: use the first valid local time.
		}
		if oldTime.Before(transition) && !newTime.Before(transition) {
			return oldTime.In(r.location) // Fall overlap: use the first occurrence.
		}
	}
	return fire
}

func IsDue(now time.Time, clock, timezone string) (time.Time, bool) {
	r, ok := parseReminderTime(clock, timezone)
	if !ok {
		return time.Time{}, false
	}
	day := r.day(now, 0)
	return (reminderTime{location: r.location}).fire(day), !now.Before(r.fire(day))
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now().UTC()
}

func (s *Service) RunOnce() error {
	now := s.now()
	targets, err := s.Store.ListReminderTargets()
	if err != nil {
		return err
	}
	for _, target := range targets {
		reminderDate, due := IsDue(now, target.Time, target.Timezone)
		if !due {
			continue
		}
		s.deliver(target, reminderDate, now)
	}
	return nil
}

// deliver returns the next persisted attempt (if any) and whether the target was removed.
func (s *Service) deliver(target model.ReminderTarget, reminderDate, now time.Time) (retryAt time.Time, removed bool) {
	claimed, retryAt, err := s.Store.ClaimReminderDelivery(target, reminderDate, now)
	if err != nil {
		log.Printf("claim reminder for user %s: %v", target.UserID, err)
		return s.now().Add(store.ReminderDeliveryLease), false
	}
	if !claimed {
		return retryAt, false
	}
	localDate := reminderDate.Format("2006-01-02")
	payload, _ := json.Marshal(map[string]string{
		"title": "217",
		"body":  "Hora de registrar seu anticoncepcional • Time to record your medication",
		"url":   "/?reminder=1",
		"date":  localDate,
		"tag":   "217-reminder-" + localDate,
	})
	permanent, sendErr := s.Sender.Send(target, payload)
	if sendErr != nil {
		log.Printf("send reminder for user %s: %v", target.UserID, sendErr)
		if permanent {
			if err := s.Store.DeletePushSubscription(target.UserID, target.Endpoint); err == nil {
				return time.Time{}, true
			} else {
				log.Printf("remove push subscription for user %s: %v", target.UserID, err)
			}
		}
	}
	retryAt, err = s.Store.FinishReminderDelivery(target.SubscriptionID, reminderDate, sendErr == nil, s.now())
	if err != nil {
		log.Printf("finish reminder for user %s: %v", target.UserID, err)
		return now.Add(store.ReminderDeliveryLease), false
	}
	return retryAt, false
}

type scheduledReminder struct {
	target model.ReminderTarget
	clock  reminderTime
	next   time.Time
}

func (s *Service) reload(previous map[string]scheduledReminder) (map[string]scheduledReminder, error) {
	targets, err := s.Store.ListReminderTargets()
	if err != nil {
		return nil, err
	}
	now := s.now()
	schedule := make(map[string]scheduledReminder, len(targets))
	for _, target := range targets {
		if old, ok := previous[target.SubscriptionID]; ok && old.target.Time == target.Time && old.target.Timezone == target.Timezone {
			old.target = target
			schedule[target.SubscriptionID] = old
		} else if clock, ok := parseReminderTime(target.Time, target.Timezone); ok {
			schedule[target.SubscriptionID] = scheduledReminder{target, clock, clock.fire(clock.day(now, 0))}
		}
	}
	return schedule, nil
}

// Run owns the in-memory schedule. Run the API with replicas: 1 when Web Push
// is enabled: Notify is local to this process, not a cross-replica signal.
func (s *Service) Run(stop <-chan struct{}) {
	notify := s.notifications()
	var schedule map[string]scheduledReminder
	var backoff time.Duration
	reloadAt := s.now()
	for {
		select {
		case <-stop:
			return
		default:
		}
		select {
		case <-notify:
			reloadAt, backoff = s.now(), 0
		default:
		}
		now := s.now()
		wake := reloadAt
		if !reloadAt.IsZero() {
			// Do not send from the old schedule after a failed reload: a user
			// may have withdrawn consent or removed their subscription.
			if !reloadAt.After(now) {
				updated, err := s.reload(schedule)
				if err != nil {
					log.Printf("reminder scheduler: %v", err)
					backoff = min(max(5*time.Second, backoff*2), 5*time.Minute)
					reloadAt = s.now().Add(backoff)
				} else {
					schedule, reloadAt, backoff = updated, time.Time{}, 0
				}
				continue
			}
		} else {
			var next scheduledReminder
			for _, candidate := range schedule {
				if wake.IsZero() || candidate.next.Before(wake) {
					wake, next = candidate.next, candidate
				}
			}
			if !wake.IsZero() && !wake.After(now) {
				id := next.target.SubscriptionID
				day := next.clock.day(now, 0)
				if fire := next.clock.fire(day); now.Before(fire) {
					// A late wake may land on a new day before its due time.
					next.next = fire
				} else {
					retryAt, removed := s.deliver(next.target, day, now)
					if removed {
						delete(schedule, id)
						continue
					}
					tomorrow := next.clock.day(now, 1)
					next.next = next.clock.fire(tomorrow)
					if retryAt.After(now) && retryAt.Before((reminderTime{location: next.clock.location}).fire(tomorrow)) {
						next.next = retryAt
					}
				}
				schedule[id] = next
				continue
			}
		}

		reload, stopped := waitForSchedule(stop, notify, wake, now)
		if stopped {
			return
		}
		if reload {
			reloadAt, backoff = s.now(), 0
		}
	}
}

func waitForSchedule(stop, notify <-chan struct{}, wake, now time.Time) (reload, stopped bool) {
	var tick <-chan time.Time
	if !wake.IsZero() {
		timer := time.NewTimer(wake.Sub(now))
		defer timer.Stop() // Go timers are synchronous; there is no stale tick to drain.
		tick = timer.C
	}
	select {
	case <-stop:
		return false, true
	case <-notify:
		return true, false
	case <-tick:
		return false, false
	}
}
