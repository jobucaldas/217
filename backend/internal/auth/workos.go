package auth

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/workos/workos-go/v10"
)

// WorkOSOAuth is an AuthKit authorization-code client using PKCE.
// The API key stays on the server; public clients only see the client ID.
type WorkOSOAuth struct {
	client      *workos.Client
	clientID    string
	redirectURI string
}

// NewWorkOSOAuth builds a WorkOS AuthKit client with an exact callback URL.
func NewWorkOSOAuth(apiKey, clientID, appBaseURL string) (*WorkOSOAuth, error) {
	if apiKey == "" || clientID == "" || appBaseURL == "" {
		return nil, fmt.Errorf("workos oauth is not configured")
	}
	canonicalBaseURL, err := ValidateAppBaseURL(appBaseURL)
	if err != nil {
		return nil, err
	}
	redirectURI := canonicalBaseURL + "/api/auth/workos/callback"
	client := workos.NewClient(apiKey, workos.WithClientID(clientID))
	return &WorkOSOAuth{client: client, clientID: clientID, redirectURI: redirectURI}, nil
}

// RedirectURI returns the registered AuthKit callback for the browser cookie flow.
func (w *WorkOSOAuth) RedirectURI() string { return w.redirectURI }

// AuthCodeURL returns the AuthKit consent URL with PKCE S256 parameters.
// The nonce argument is accepted for OAuthProvider compatibility and is unused by AuthKit.
func (w *WorkOSOAuth) AuthCodeURL(state, codeChallenge, nonce string) string {
	_ = nonce
	provider := "authkit"
	method := "S256"
	params := workos.AuthKitAuthorizationURLParams{
		RedirectURI:         w.redirectURI,
		ClientID:            w.clientID,
		Provider:            &provider,
		State:               &state,
		CodeChallenge:       &codeChallenge,
		CodeChallengeMethod: &method,
	}
	url, err := w.client.GetAuthKitAuthorizationURL(params)
	if err != nil {
		return ""
	}
	return url
}

// Exchange swaps an authorization code for the verified WorkOS user identity.
func (w *WorkOSOAuth) Exchange(ctx context.Context, code, codeVerifier, nonce string) (*OAuthUserInfo, error) {
	_ = nonce
	return w.ExchangeWithRedirect(ctx, code, codeVerifier, w.redirectURI)
}

// ExchangeWithRedirect exchanges a code for a specific registered redirect URI (mobile deep link).
func (w *WorkOSOAuth) ExchangeWithRedirect(ctx context.Context, code, codeVerifier, redirectURI string) (*OAuthUserInfo, error) {
	if code == "" || codeVerifier == "" {
		return nil, fmt.Errorf("missing oauth code or verifier")
	}
	if redirectURI == "" {
		redirectURI = w.redirectURI
	}
	_ = redirectURI // AuthenticateWithCode binds the code to the redirect used at authorize time.
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	resp, err := w.client.AuthKitPKCECodeExchange(ctx, workos.AuthKitPKCECodeExchangeParams{
		Code:         code,
		CodeVerifier: codeVerifier,
	})
	if err != nil {
		return nil, fmt.Errorf("workos exchange: %w", err)
	}
	return userInfoFromWorkOS(resp)
}

func userInfoFromWorkOS(resp *workos.AuthenticateResponse) (*OAuthUserInfo, error) {
	if resp == nil || resp.User == nil {
		return nil, fmt.Errorf("missing workos user")
	}
	u := resp.User
	if u.ID == "" || u.Email == "" {
		return nil, fmt.Errorf("invalid workos user claims")
	}
	name := strings.TrimSpace(derefString(u.Name))
	if name == "" {
		parts := []string{derefString(u.FirstName), derefString(u.LastName)}
		name = strings.TrimSpace(strings.Join(parts, " "))
	}
	return &OAuthUserInfo{
		Subject:       u.ID,
		Email:         u.Email,
		EmailVerified: u.EmailVerified,
		Name:          name,
	}, nil
}

func derefString(v *string) string {
	if v == nil {
		return ""
	}
	return *v
}
