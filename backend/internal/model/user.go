package model

import "time"

type User struct {
	ID           string    `json:"id"`
	Email        string    `json:"email"`
	Name         string    `json:"name"`
	Role         string    `json:"role"`
	PasswordHash string    `json:"-"`
	APIKey       string    `json:"api_key,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
	// ConsentVersion is the privacy notice version agreed to (0 = none yet).
	ConsentVersion int        `json:"consent_version"`
	ConsentedAt    *time.Time `json:"consented_at,omitempty"`
}

// HasConsent reports whether the user agreed to the current privacy notice.
func (u *User) HasConsent() bool {
	return u != nil && u.ConsentVersion >= ConsentVersion
}

// EffectiveRole returns owner, partner, or "" while the user has not chosen.
func (u *User) EffectiveRole() string {
	if u == nil {
		return ""
	}
	return NormalizeRole(u.Role)
}

// NormalizeRole maps a stored role to owner, partner, or "" (not chosen yet).
func NormalizeRole(role string) string {
	switch role {
	case RoleOwner, RolePartner:
		return role
	default:
		return ""
	}
}
