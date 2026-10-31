package model

import "time"

// ConsentVersion is the privacy notice version users must agree to before
// the API processes their data. Bump it when the notice changes materially:
// everyone is asked again.
const ConsentVersion = 1

// RetentionAfterRevoke is how long a revoked share (who followed whose
// calendar) is kept before it is purged.
const RetentionAfterRevoke = 30 * 24 * time.Hour

// AccountExport is everything the API holds about one account (LGPD art. 18:
// access and portability).
type AccountExport struct {
	ExportedAt        time.Time                `json:"exported_at"`
	User              *User                    `json:"user"`
	Share             *ShareState              `json:"share"`
	Entries           []*Entry                 `json:"entries"`
	MessagesReceived  []*Message               `json:"messages_received"`
	MessagesSent      []*Message               `json:"messages_sent"`
	Reminder          *ReminderPreference      `json:"reminder_preference"`
	PartnerAlerts     *PartnerAlertPreference  `json:"partner_alerts,omitempty"`
	PushSubscriptions []ExportPushSubscription `json:"push_subscriptions"`
	Shares            []*CalendarShare         `json:"shares"`
}
