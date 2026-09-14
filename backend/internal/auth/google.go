package auth

import (
	"context"
	"crypto/subtle"
	"fmt"
	"net/http"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"golang.org/x/oauth2"
)

const (
	googleAuthURL  = "https://accounts.google.com/o/oauth2/v2/auth"
	googleTokenURL = "https://oauth2.googleapis.com/token"
	googleJWKSURL  = "https://www.googleapis.com/oauth2/v3/certs"
)

// GoogleOAuth is a concrete OAuth2 authorization-code client for Google.
type GoogleOAuth struct {
	config     *oauth2.Config
	verifier   *oidc.IDTokenVerifier
	httpClient *http.Client
}

// NewGoogleOAuth builds a Google authorization-code client with an exact callback URL.
func NewGoogleOAuth(clientID, clientSecret, appBaseURL string) (*GoogleOAuth, error) {
	if clientID == "" || clientSecret == "" || appBaseURL == "" {
		return nil, fmt.Errorf("google oauth is not configured")
	}
	canonicalBaseURL, err := ValidateAppBaseURL(appBaseURL)
	if err != nil {
		return nil, err
	}
	redirectURL := canonicalBaseURL + "/api/auth/google/callback"
	client := &http.Client{Timeout: 10 * time.Second}
	keys := oidc.NewRemoteKeySet(oidc.ClientContext(context.Background(), client), googleJWKSURL)
	return &GoogleOAuth{
		config: &oauth2.Config{
			ClientID:     clientID,
			ClientSecret: clientSecret,
			RedirectURL:  redirectURL,
			Scopes:       []string{"openid", "email", "profile"},
			Endpoint: oauth2.Endpoint{
				AuthURL:  googleAuthURL,
				TokenURL: googleTokenURL,
			},
		},
		httpClient: client,
		verifier:   oidc.NewVerifier("https://accounts.google.com", keys, &oidc.Config{ClientID: clientID}),
	}, nil
}

// AuthCodeURL returns the Google consent URL with PKCE S256 parameters.
func (g *GoogleOAuth) AuthCodeURL(state, codeChallenge, nonce string) string {
	return g.config.AuthCodeURL(
		state,
		oidc.Nonce(nonce),
		oauth2.SetAuthURLParam("code_challenge", codeChallenge),
		oauth2.SetAuthURLParam("code_challenge_method", "S256"),
		oauth2.SetAuthURLParam("prompt", "select_account"),
	)
}

// Exchange swaps an authorization code for the verified Google account identity.
func (g *GoogleOAuth) Exchange(ctx context.Context, code, codeVerifier, nonce string) (*OAuthUserInfo, error) {
	if nonce == "" {
		return nil, fmt.Errorf("missing oauth nonce")
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	ctx = oidc.ClientContext(ctx, g.httpClient)
	token, err := g.config.Exchange(ctx, code, oauth2.SetAuthURLParam("code_verifier", codeVerifier))
	if err != nil {
		return nil, fmt.Errorf("oauth exchange: %w", err)
	}
	rawIDToken, ok := token.Extra("id_token").(string)
	if !ok || rawIDToken == "" {
		return nil, fmt.Errorf("missing google id token")
	}
	idToken, err := g.verifier.Verify(ctx, rawIDToken)
	if err != nil {
		return nil, fmt.Errorf("invalid google id token: %w", err)
	}
	if idToken.Subject == "" || subtle.ConstantTimeCompare([]byte(idToken.Nonce), []byte(nonce)) != 1 {
		return nil, fmt.Errorf("invalid google subject or nonce")
	}
	var payload struct {
		Sub             string `json:"sub"`
		Email           string `json:"email"`
		EmailVerified   bool   `json:"email_verified"`
		Name            string `json:"name"`
		HostedDomain    string `json:"hd"`
		AuthorizedParty string `json:"azp"`
	}
	if err := idToken.Claims(&payload); err != nil {
		return nil, fmt.Errorf("decoding id token claims: %w", err)
	}
	if payload.Email == "" || (payload.AuthorizedParty != "" && payload.AuthorizedParty != g.config.ClientID) || (len(idToken.Audience) > 1 && payload.AuthorizedParty != g.config.ClientID) {
		return nil, fmt.Errorf("invalid google email or authorized party")
	}
	return &OAuthUserInfo{
		Subject:       idToken.Subject,
		Email:         payload.Email,
		EmailVerified: payload.EmailVerified,
		Name:          payload.Name,
		HostedDomain:  payload.HostedDomain,
	}, nil
}
