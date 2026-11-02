package model

import "time"

type User struct {
	ID    string `json:"id"`
	Email string `json:"email"`
	Name  string `json:"name"`
	Role  string `json:"role"`
	Stage string `json:"stage"`
	// DisplayName is the name the user chose to show the other side
	// (Messages, share screens); empty falls back to Name (WorkOS profile).
	DisplayName string `json:"display_name"`
	// BirthDate is the owner's birth month, YYYY-MM (empty = not given).
	BirthDate    string    `json:"birth_date,omitempty"`
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

const (
	StageCycling       = "cycling"
	StagePerimenopause = "perimenopause"
	StageMenopause     = "menopause"

	// MaxDisplayNameRunes bounds a user-chosen display name.
	MaxDisplayNameRunes = 60
)

// ValidStage reports whether stage is one of the reproductive stages.
func ValidStage(stage string) bool {
	return stage == StageCycling || stage == StagePerimenopause || stage == StageMenopause
}

// PublicName is the name shown to the other side of a share: the chosen
// display name, or the sign-in profile name when none is set.
func (u *User) PublicName() string {
	if u == nil {
		return ""
	}
	if u.DisplayName != "" {
		return u.DisplayName
	}
	return u.Name
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
