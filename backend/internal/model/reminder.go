package model

import "time"

const (
	DefaultReminderTime     = "20:00"
	DefaultReminderTimezone = "UTC"
	MaxPushSubscriptions    = 5
	// DefaultRepeatMinutes seeds the field the first time an owner turns
	// the repeat on.
	DefaultRepeatMinutes = 15
	MinRepeatMinutes     = 1
	MaxRepeatMinutes     = 120
)

type ReminderPreference struct {
	Enabled  bool   `json:"enabled"`
	Time     string `json:"time"`
	Timezone string `json:"timezone"`
	// RepeatEnabled repeats the "pill not logged" reminder every
	// RepeatMinutes until today's pill is logged or the day ends.
	RepeatEnabled     bool      `json:"repeat_enabled"`
	RepeatMinutes     int       `json:"repeat_minutes"`
	SubscriptionCount int       `json:"subscription_count"`
	Deliverable       bool      `json:"deliverable"`
	CreatedAt         time.Time `json:"created_at,omitempty"`
	UpdatedAt         time.Time `json:"updated_at,omitempty"`
}

// ValidRepeatMinutes reports whether minutes is in the allowed interval,
// regardless of whether the repeat is currently enabled.
func ValidRepeatMinutes(minutes int) bool {
	return minutes >= MinRepeatMinutes && minutes <= MaxRepeatMinutes
}

type PushSubscriptionRequest struct {
	Endpoint string `json:"endpoint"`
	Keys     struct {
		P256DH string `json:"p256dh"`
		Auth   string `json:"auth"`
	} `json:"keys"`
}

type PushSubscription struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Endpoint  string    `json:"endpoint"`
	P256DH    string    `json:"-"`
	Auth      string    `json:"-"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type ReminderTarget struct {
	SubscriptionID string
	UserID         string
	UserName       string
	Endpoint       string
	P256DH         string
	Auth           string
	Time           string
	Timezone       string
}

type ExportPushSubscription struct {
	Endpoint string `json:"endpoint"`
}
