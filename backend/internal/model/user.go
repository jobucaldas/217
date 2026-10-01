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
}

// EffectiveRole returns owner when role is unset (pre-migration rows).
func (u *User) EffectiveRole() string {
	if u == nil || u.Role == "" {
		return RoleOwner
	}
	return u.Role
}
