package store

import (
	"time"

	"217/backend/internal/model"
)

type Store interface {
	CreateUser(email, name, password string) (*model.User, error)
	GetUserByEmail(email string) (*model.User, error)
	GetUserByID(userID string) (*model.User, error)
	LinkWorkOSIdentity(subject, verifiedEmail, name string, authoritative bool) (*model.User, error)
	WorkOSSubject(userID string) (string, error)
	DeleteUser(userID string) error

	GetEntry(userID, date string) (*model.Entry, error)
	ListEntries(userID string, year, month int) ([]*model.Entry, error)
	UpsertEntry(userID, date string, req model.UpsertRequest) (*model.Entry, error)
	DeleteEntry(userID, date string) error
	GetStats(userID string, year, month int) (*model.Stats, error)
	// ListPeriodDays returns YYYY-MM-DD dates marked as period within [from, to].
	ListPeriodDays(userID, from, to string) ([]string, error)

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
	CreateSession(userID, sessionID string, expiresAt time.Time) error
	GetUserBySession(sessionID string) (*model.User, error)
	DeleteSession(sessionID string) error
	DeleteAllSessionsForUser(userID string) error

	// Calendar sharing (owner ↔ partner)
	GetShareState(userID string) (*model.ShareState, error)
	EnableShare(ownerID string) (*model.ShareState, error)
	RevokeShare(ownerID string) (*model.ShareState, error)
	AcceptShare(partnerID, inviteCode string) (*model.ShareState, error)
	CalendarSubjectID(userID string) (string, error)
	// SetRole picks owner or partner; switching is refused while a share is live.
	SetRole(userID, role string) (*model.User, error)

	// Partner notification preferences (PMS heads-up, pill not logged)
	GetPartnerAlerts(userID string) (*model.PartnerAlertPreference, error)
	UpsertPartnerAlerts(userID string, pref model.PartnerAlertPreference) (*model.PartnerAlertPreference, error)

	// Partner → owner inbox notes
	ListInboxNotes(ownerID string) ([]*model.PartnerNote, error)
	CreatePartnerNote(partnerID, body string) (*model.PartnerNote, error)
	MarkInboxNoteRead(ownerID, noteID string) error

	Close() error
}

type OAuthAttempt struct {
	CodeVerifier string
	Nonce        string
}
