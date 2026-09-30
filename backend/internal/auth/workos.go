package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/workos/workos-go/v10"
)

const workosAPIDefault = "https://api.workos.com"

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
	_ = redirectURI
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

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
	if w.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+w.apiKey)
	}

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
