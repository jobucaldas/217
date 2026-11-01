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

	// Device keys renew sessions on a device without a new sign-in.
	// CreateDeviceKey registers a PKIX public key and returns its ID.
	CreateDeviceKey(userID string, publicKey []byte) (string, error)
	// CreateDeviceSession is CreateSession bound to a device key, so
	// revoking the key ends the session too.
	CreateDeviceSession(userID, keyID, sessionID string, expiresAt time.Time) error
	// SetDeviceChallenge stores a single-use challenge for keyID.
	SetDeviceChallenge(keyID, challenge string, expiresAt time.Time) error
	// ConsumeDeviceChallenge clears the key's challenge and, when it matches
	// and has not expired, returns the key's owner and public key.
	ConsumeDeviceChallenge(keyID, challenge string) (userID string, publicKey []byte, err error)
	// DeleteSessionAndDevice ends a session and revokes the device key it
	// is bound to, if any (logout).
	DeleteSessionAndDevice(sessionID string) error
	ListDeviceKeys(userID string) ([]model.DeviceKey, error)

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

	// Messages between an owner and her linked partner, both directions.
	// ListMessages returns every message the user sent or received, newest
	// first (inbox and export).
	ListMessages(userID string) ([]*model.Message, error)
	// SendMessage writes to the other side of the user's active share.
	SendMessage(senderID, body string) (*model.Message, error)
	// MarkMessageRead marks a message the user received as read.
	MarkMessageRead(userID, messageID string) error
	ListAccountShares(userID string) ([]*model.CalendarShare, error)
	ListAccountSubscriptions(userID string) ([]model.ExportPushSubscription, error)

	Close() error
}

type OAuthAttempt struct {
	CodeVerifier string
	Nonce        string
	// RedirectURI is the browser callback chosen at login; empty for attempts that predate it.
	RedirectURI string
}
