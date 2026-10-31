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

// Message is a note between a calendar owner and her linked partner, in
// either direction. Sender is the role that wrote it (owner or partner).
type Message struct {
	ID        string     `json:"id"`
	OwnerID   string     `json:"owner_id"`
	PartnerID string     `json:"partner_id"`
	Sender    string     `json:"sender"`
	Body      string     `json:"body"`
	CreatedAt time.Time  `json:"created_at"`
	ReadAt    *time.Time `json:"read_at,omitempty"`
	FromName  string     `json:"from_name,omitempty"`
	FromEmail string     `json:"from_email,omitempty"`
	// FromMe is true when the caller wrote the message (viewer-relative).
	FromMe bool `json:"from_me"`
}

// SenderID is the user who wrote the message.
func (m *Message) SenderID() string {
	if m.Sender == RoleOwner {
		return m.OwnerID
	}
	return m.PartnerID
}

// RecipientID is the user the message was written to.
func (m *Message) RecipientID() string {
	if m.Sender == RoleOwner {
		return m.PartnerID
	}
	return m.OwnerID
}

// SessionPayload is returned by /api/auth/session and OAuth exchange.
type SessionPayload struct {
	User  *User       `json:"user"`
	Share *ShareState `json:"share"`
}
