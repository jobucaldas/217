package store

import (
	"errors"
	"time"

	"217/backend/internal/model"
)

var (
	// ErrSessionNotFound indicates the session token is missing, expired, or bound to an idle/revoked device key.
	ErrSessionNotFound = errors.New("session not found")
	// ErrDeviceKeyNotFound indicates a missing or inactive device key.
	ErrDeviceKeyNotFound = errors.New("device key not found")
	// ErrEntryNotFound indicates no calendar entry exists for the requested date.
	ErrEntryNotFound          = errors.New("entry not found")
	ErrUserNotFound           = errors.New("user not found")
	ErrMessageNotFound        = errors.New("message not found")
	ErrDeviceChallengeInvalid = errors.New("invalid or expired challenge")
	ErrRoleNotChosen          = errors.New("role not chosen")
	ErrShareInactive          = errors.New("share inactive")
	ErrOnlySignInMethod       = errors.New("set up another sign-in method first")
	ErrOIDCAccountExists      = errors.New("account exists: sign in and connect from settings")
)

// ReminderDeliveryLease is how long a crashed sender's claim stays exclusive.
const ReminderDeliveryLease = 5 * time.Minute

type Store interface {
	CreateUser(email, name, password string) (*model.User, error)
	GetUserByEmail(email string) (*model.User, error)
	GetUserByID(userID string) (*model.User, error)
	LinkWorkOSIdentity(subject, verifiedEmail, name string, authoritative bool) (*model.User, error)
	WorkOSSubject(userID string) (string, error)
	LinkOIDCIdentity(issuer, subject, email, name string, verified bool) (*model.User, error)
	AttachOIDCIdentity(userID, issuer, subject string) error
	DeleteOIDCIdentity(userID, issuer string) error
	OIDCIdentities(userID string) ([]model.OIDCIdentity, error)
	RemoveSignInMethod(userID, issuer string, password, passwordEnabled, workosEnabled bool) error
	// DeleteUser removes the account and everything it owns; a share it
	// followed as partner is revoked so the owner can invite someone else.
	DeleteUser(userID string) error
	// RecordConsent stores that the user agreed to privacy notice version;
	// version 0 withdraws consent (and clears when it was given).
	RecordConsent(userID string, version int) (*model.User, error)
	// PurgeExpired drops data past its retention: expired sessions and
	// sign-in attempts, idle device keys, old deliveries and long-revoked shares.
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
	// ClaimReminderDelivery rechecks the cached target. A denied claim returns
	// the end of its lease/backoff, or zero if sent or no longer eligible.
	ClaimReminderDelivery(target model.ReminderTarget, reminderDate, now time.Time) (claimed bool, retryAt time.Time, err error)
	// FinishReminderDelivery returns the persisted retry time after a failed send.
	FinishReminderDelivery(subscriptionID string, reminderDate time.Time, sent bool, now time.Time) (retryAt time.Time, err error)

	// OAuth attempts
	CreateOAuthAttempt(state, binding, codeVerifier, nonce, redirectURI string, expiresAt time.Time) error
	ConsumeOAuthAttempt(state, binding string) (OAuthAttempt, error)

	// Session management
	CreateSession(userID, sessionID string, expiresAt time.Time) error
	GetUserBySession(sessionID string) (*model.User, error)
	// GetSessionPrincipal is GetUserBySession plus the session's expiry.
	GetSessionPrincipal(sessionID string) (*model.User, time.Time, error)
	// SessionCreatedAt is when the session was signed in (re-authentication checks).
	SessionCreatedAt(sessionID string) (time.Time, error)
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
	// ActivePeer returns the other side of the user's active share, or "".
	ActivePeer(userID string) (string, error)
	// SetPasswordCredential stores (or replaces) the password hash of userID.
	SetPasswordCredential(userID string, hash string) error
	// GetPasswordCredential returns the stored hash for userID, or "" with a
	// nil error when the user has no password credential.
	GetPasswordCredential(userID string) (string, error)
	// LookupPasswordHashByEmail resolves a sign-in email to its credential
	// hash ("" when the user or credential does not exist).
	LookupPasswordHashByEmail(email string) (userID string, hash string, err error)
	// CreateEmailVerification stores a single-use code forcing the user to
	// verify the address before the next password login (mail configured).
	CreateEmailVerification(userID, code string, expiresAt time.Time) error
	// RefreshEmailVerification replaces a pending code without creating one.
	RefreshEmailVerification(userID, code string, expiresAt time.Time) (bool, error)
	// HasEmailVerification reports a pending verification for userID,
	// however old: it is what blocks a password login until the address
	// is verified (resend renews it; only a consumed code clears it).
	HasEmailVerification(userID string) (bool, error)
	// ConsumeEmailVerification clears a pending code, reporting whether it
	// matched (single use; the stored value is only a hash of the code).
	ConsumeEmailVerification(userID, code string) (bool, error)
	// DeletePasswordCredential removes the password sign-in method.
	DeletePasswordCredential(userID string) error
	// ErrEmailTaken reports whether err is the email-already-registered
	// failure of CreatePasswordUser (the handler answers it with 409).
	ErrEmailTaken(err error) bool
	// CreatePasswordUser creates the account with its password hash and
	// (when code is not empty) the address verification row in one step,
	// under the same per-email lock as the WorkOS link: concurrent signups
	// for one email produce exactly one account, the rest get a taken error.
	CreatePasswordUser(email, passwordHash, verificationCode string, verificationExpires time.Time) (*model.User, error)
	// SetRole picks owner or partner; switching is refused while a share is live.
	SetRole(userID, role string) (*model.User, error)
	SetStage(userID, stage string) (*model.User, error)
	// SetProfile updates the display name and/or birth month (YYYY-MM); a
	// nil field is kept, an empty one cleared. Callers validate the values.
	SetProfile(userID string, displayName, birthDate *string) (*model.User, error)

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
