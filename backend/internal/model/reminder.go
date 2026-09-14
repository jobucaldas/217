package model

import "time"

const (
	DefaultReminderTime     = "20:00"
	DefaultReminderTimezone = "UTC"
	MaxPushSubscriptions    = 5
)

type ReminderPreference struct {
	Enabled           bool      `json:"enabled"`
	Time              string    `json:"time"`
	Timezone          string    `json:"timezone"`
	SubscriptionCount int       `json:"subscription_count"`
	Deliverable       bool      `json:"deliverable"`
	CreatedAt         time.Time `json:"created_at,omitempty"`
	UpdatedAt         time.Time `json:"updated_at,omitempty"`
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
