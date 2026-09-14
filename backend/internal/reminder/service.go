package reminder

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
	"time"

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
}

func IsDue(now time.Time, reminderTime, timezone string) (time.Time, bool) {
	location, err := time.LoadLocation(timezone)
	if err != nil {
		return time.Time{}, false
	}
	parts := strings.Split(reminderTime, ":")
	if len(parts) != 2 {
		return time.Time{}, false
	}
	parsed, err := time.Parse("15:04", reminderTime)
	if err != nil {
		return time.Time{}, false
	}
	localNow := now.In(location)
	dueAt := time.Date(localNow.Year(), localNow.Month(), localNow.Day(), parsed.Hour(), parsed.Minute(), 0, 0, location)
	return time.Date(localNow.Year(), localNow.Month(), localNow.Day(), 0, 0, 0, 0, location), !localNow.Before(dueAt)
}

func (s Service) RunOnce() error {
	now := time.Now().UTC()
	if s.Now != nil {
		now = s.Now()
	}
	targets, err := s.Store.ListReminderTargets()
	if err != nil {
		return err
	}
	for _, target := range targets {
		reminderDate, due := IsDue(now, target.Time, target.Timezone)
		if !due {
			continue
		}
		claimed, err := s.Store.ClaimReminderDelivery(target.SubscriptionID, reminderDate, now)
		if err != nil || !claimed {
			if err != nil {
				log.Printf("claim reminder for user %s: %v", target.UserID, err)
			}
			continue
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
		if sendErr == nil {
			if err := s.Store.FinishReminderDelivery(target.SubscriptionID, reminderDate, true, now); err != nil {
				log.Printf("finish reminder for user %s: %v", target.UserID, err)
			}
			continue
		}
		log.Printf("send reminder for user %s: %v", target.UserID, sendErr)
		_ = s.Store.FinishReminderDelivery(target.SubscriptionID, reminderDate, false, now)
		if permanent {
			_ = s.Store.DeletePushSubscription(target.UserID, target.Endpoint)
		}
	}
	return nil
}

func (s Service) Run(stop <-chan struct{}) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	_ = s.RunOnce()
	for {
		select {
		case <-ticker.C:
			if err := s.RunOnce(); err != nil {
				log.Printf("reminder scheduler: %v", err)
			}
		case <-stop:
			return
		}
	}
}
