package model

import "time"

const (
	RoleOwner   = "owner"
	RolePartner = "partner"

	ShareNone    = "none"
	ShareOpen    = "open"
	ShareActive  = "active"
	ShareRevoked = "revoked"
)

// ShareState is the session/API view of calendar sharing.
type ShareState struct {
	Status          string `json:"status"`
	InviteCode      string `json:"invite_code,omitempty"`
	InviteURL       string `json:"invite_url,omitempty"`
	PartnerEmail    string `json:"partner_email,omitempty"`
	PartnerName     string `json:"partner_name,omitempty"`
	OwnerName       string `json:"owner_name,omitempty"`
	OwnerEmail      string `json:"owner_email,omitempty"`
	CanEditCalendar bool   `json:"can_edit_calendar"`
	UnreadNotes     int    `json:"unread_notes,omitempty"`
}

// CalendarShare is the persisted share row.
type CalendarShare struct {
	ID         string
	OwnerID    string
	PartnerID  string
	InviteCode string
	Status     string
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

// PartnerNote is a general note from partner to owner inbox.
type PartnerNote struct {
	ID        string     `json:"id"`
	OwnerID   string     `json:"owner_id"`
	PartnerID string     `json:"partner_id"`
	Body      string     `json:"body"`
	CreatedAt time.Time  `json:"created_at"`
	ReadAt    *time.Time `json:"read_at,omitempty"`
	FromName  string     `json:"from_name,omitempty"`
	FromEmail string     `json:"from_email,omitempty"`
}

// SessionPayload is returned by /api/auth/session and OAuth exchange.
type SessionPayload struct {
	User  *User       `json:"user"`
	Share *ShareState `json:"share"`
}
