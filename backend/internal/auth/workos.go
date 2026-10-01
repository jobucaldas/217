package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/workos/workos-go/v10"
)

const workosAPIDefault = "https://api.workos.com"

// NativeAuthRedirectURI is the Android AuthKit callback registered for this app.
// Custom schemes are not exclusive across apps, so this allowlist is not a substitute for PKCE.
const NativeAuthRedirectURI = "com.jobucaldas.a217://auth/callback"

// WorkOSOAuth is an AuthKit authorization-code client using PKCE.
// Native exchange uses the public client_id + code_verifier path (no API key required).
type WorkOSOAuth struct {
	client      *workos.Client
	httpClient  *http.Client
	apiBaseURL  string
	clientID    string
	redirectURI string
	apiKey      string
}

// NewWorkOSOAuth builds a WorkOS AuthKit client with an exact browser callback URL.
// apiKey may be empty for PKCE-only native exchange.
func NewWorkOSOAuth(apiKey, clientID, appBaseURL string) (*WorkOSOAuth, error) {
	if clientID == "" || appBaseURL == "" {
		return nil, fmt.Errorf("workos oauth is not configured")
	}
	canonicalBaseURL, err := ValidateAppBaseURL(appBaseURL)
	if err != nil {
		return nil, err
	}
	redirectURI := canonicalBaseURL + "/api/auth/workos/callback"
	client := workos.NewClient(apiKey, workos.WithClientID(clientID))
	return &WorkOSOAuth{
		client:      client,
		httpClient:  &http.Client{Timeout: 15 * time.Second},
		apiBaseURL:  workosAPIDefault,
		clientID:    clientID,
		redirectURI: redirectURI,
		apiKey:      apiKey,
	}, nil
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
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	if redirectURI != w.redirectURI && redirectURI != NativeAuthRedirectURI {
		return nil, fmt.Errorf("redirect uri is not registered")
	}
	// Public PKCE client: code_verifier is the only client authenticator.
	// WorkOS treats code_verifier as optional once a client secret is present, so the
	// API key must not be sent here (neither Authorization nor client_secret).
	payload := map[string]string{
		"grant_type":    "authorization_code",
		"client_id":     w.clientID,
		"code":          code,
		"code_verifier": codeVerifier,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(w.apiBaseURL, "/")+"/user_management/authenticate", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := w.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("workos exchange: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("workos exchange: status %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))
	}
	var parsed workos.AuthenticateResponse
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return nil, fmt.Errorf("workos exchange decode: %w", err)
	}
	return userInfoFromWorkOS(&parsed)
}

// DeleteUser permanently deletes the AuthKit user (DELETE /user_management/users/{id}).
// A missing user (already deleted) is treated as success so retries stay idempotent.
func (w *WorkOSOAuth) DeleteUser(ctx context.Context, workosUserID string) error {
	if w == nil || w.apiKey == "" {
		return fmt.Errorf("workos user delete requires WORKOS_API_KEY")
	}
	if workosUserID == "" {
		return fmt.Errorf("missing workos user id")
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	err := w.client.UserManagement().Delete(ctx, workosUserID)
	if err == nil {
		return nil
	}
	var notFound *workos.NotFoundError
	if errors.As(err, &notFound) {
		return nil
	}
	return fmt.Errorf("workos delete user: %w", err)
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
