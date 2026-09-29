package store

import (
	"time"

	"217/backend/internal/model"
)

type Store interface {
	CreateUser(email, name, password string) (*model.User, error)
	GetUserByEmail(email string) (*model.User, error)
	LinkGoogleIdentity(subject, verifiedEmail, name string, authoritative bool) (*model.User, error)

	GetEntry(userID, date string) (*model.Entry, error)
	ListEntries(userID string, year, month int) ([]*model.Entry, error)
	UpsertEntry(userID, date string, req model.UpsertRequest) (*model.Entry, error)
	GetStats(userID string, year, month int) (*model.Stats, error)

	GetReminderPreference(userID string) (*model.ReminderPreference, error)
	UpsertReminderPreference(userID string, preference model.ReminderPreference) (*model.ReminderPreference, error)
	SavePushSubscription(userID string, request model.PushSubscriptionRequest) (*model.PushSubscription, error)
	DeletePushSubscription(userID, endpoint string) error
	CountPushSubscriptions(userID string) (int, error)
	ListReminderTargets() ([]model.ReminderTarget, error)
	ClaimReminderDelivery(subscriptionID string, reminderDate, now time.Time) (bool, error)
	FinishReminderDelivery(subscriptionID string, reminderDate time.Time, sent bool, now time.Time) error

	// OAuth attempts
	CreateOAuthAttempt(state, binding, codeVerifier, nonce string, expiresAt time.Time) error
	ConsumeOAuthAttempt(state, binding string) (OAuthAttempt, error)

	// Session management
	CreateSession(userID, sessionID string, expiresAt time.Time, userAgent, ip string) error
	GetUserBySession(sessionID string) (*model.User, error)
	DeleteSession(sessionID string) error
	DeleteAllSessionsForUser(userID string) error

	Close() error
}

type OAuthAttempt struct {
	CodeVerifier string
	Nonce        string
}
