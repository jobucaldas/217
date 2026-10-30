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
	// DeleteUser removes the account and everything it owns; a share it
	// followed as partner is revoked so the owner can invite someone else.
	DeleteUser(userID string) error
	// RecordConsent stores that the user agreed to privacy notice version.
	RecordConsent(userID string, version int) (*model.User, error)
	// PurgeExpired drops data past its retention: expired sessions and
	// sign-in attempts, old reminder deliveries and long-revoked shares.
	PurgeExpired(now time.Time) error

	GetEntry(userID, date string) (*model.Entry, error)
	ListEntries(userID string, year, month int) ([]*model.Entry, error)
	// ListAllEntries returns every entry of the user, oldest first (export).
	ListAllEntries(userID string) ([]*model.Entry, error)
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
	CreateOAuthAttempt(state, binding, codeVerifier, nonce, redirectURI string, expiresAt time.Time) error
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
	SetStage(userID, stage string) (*model.User, error)

	// Partner notification preferences (PMS heads-up, pill not logged)
	GetPartnerAlerts(userID string) (*model.PartnerAlertPreference, error)
	UpsertPartnerAlerts(userID string, pref model.PartnerAlertPreference) (*model.PartnerAlertPreference, error)

	// Partner → owner inbox notes
	ListInboxNotes(ownerID string) ([]*model.PartnerNote, error)
	ListReceivedPartnerNotes(userID string) ([]*model.PartnerNote, error)
	CreatePartnerNote(partnerID, body string) (*model.PartnerNote, error)
	// ListSentPartnerNotes returns the notes a partner wrote (export).
	ListSentPartnerNotes(partnerID string) ([]*model.PartnerNote, error)
	ListAccountShares(userID string) ([]*model.CalendarShare, error)
	ListAccountSubscriptions(userID string) ([]model.ExportPushSubscription, error)
	MarkInboxNoteRead(ownerID, noteID string) error

	Close() error
}

type OAuthAttempt struct {
	CodeVerifier string
	Nonce        string
	// RedirectURI is the browser callback chosen at login; empty for attempts that predate it.
	RedirectURI string
}
