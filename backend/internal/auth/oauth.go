package auth

import (
	"context"
)

// OAuthUserInfo represents the minimal identity returned by an OAuth provider.
type OAuthUserInfo struct {
	Subject       string
	Email         string
	EmailVerified bool
	Name          string
	HostedDomain  string
}

// AuthoritativeEmail is true when the identity provider verified the email claim.
// WorkOS AuthKit only returns verified emails for account linking decisions here.
func (u *OAuthUserInfo) AuthoritativeEmail() bool {
	return u.EmailVerified
}

// OAuthProvider abstracts authorization URL generation and token exchange.
type OAuthProvider interface {
	AuthCodeURL(state, codeChallenge, nonce string) string
	Exchange(ctx context.Context, code, codeVerifier, nonce string) (*OAuthUserInfo, error)
}

// WorkOSExchanger optionally supports exchanging codes issued for alternate redirect URIs
// (for example a native Android deep link).
type WorkOSExchanger interface {
	ExchangeWithRedirect(ctx context.Context, code, codeVerifier, redirectURI string) (*OAuthUserInfo, error)
}

// WorkOSUserDeleter permanently removes an AuthKit user via the User Management API.
// Account deletion must invoke this before wiping local app data (fail closed).
type WorkOSUserDeleter interface {
	DeleteUser(ctx context.Context, workosUserID string) error
}
