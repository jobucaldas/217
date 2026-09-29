package auth

import (
	"context"
	"strings"
)

// OAuthUserInfo represents the minimal identity returned by an OAuth provider.
type OAuthUserInfo struct {
	Subject       string
	Email         string
	EmailVerified bool
	Name          string
	HostedDomain  string
}

// AuthoritativeEmail is only meaningful for claims from a validated Google ID token.
func (u *OAuthUserInfo) AuthoritativeEmail() bool {
	return u.EmailVerified && (strings.HasSuffix(strings.ToLower(u.Email), "@gmail.com") || u.HostedDomain != "")
}

// OAuthProvider abstracts authorization URL generation and token exchange.
type OAuthProvider interface {
	AuthCodeURL(state, codeChallenge, nonce string) string
	Exchange(ctx context.Context, code, codeVerifier, nonce string) (*OAuthUserInfo, error)
}
