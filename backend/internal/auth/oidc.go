package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"

	"github.com/coreos/go-oidc/v3/oidc"
	"golang.org/x/oauth2"
)

var ErrOIDCUnavailable = errors.New("oidc discovery unavailable")

// OIDC lazily discovers the issuer; failures are not cached.
type OIDC struct {
	Issuer, ClientID, ClientSecret, Name string
	mu                                   sync.Mutex
	provider                             *oidc.Provider
}

func (o *OIDC) Enabled() bool { return o != nil && o.Issuer != "" && o.ClientID != "" }

func (o *OIDC) discover(ctx context.Context) (*oidc.Provider, error) {
	o.mu.Lock()
	defer o.mu.Unlock()
	if o.provider != nil {
		return o.provider, nil
	}
	p, err := oidc.NewProvider(ctx, o.Issuer)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrOIDCUnavailable, err)
	}
	o.provider = p
	return p, nil
}

func (o *OIDC) config(p *oidc.Provider, redirect string) oauth2.Config {
	e := p.Endpoint()
	e.AuthStyle = oauth2.AuthStyleInHeader
	if o.ClientSecret == "" {
		// Public client: send client_id in the body, no empty Basic auth.
		e.AuthStyle = oauth2.AuthStyleInParams
	}
	return oauth2.Config{ClientID: o.ClientID, ClientSecret: o.ClientSecret, RedirectURL: redirect, Endpoint: e, Scopes: []string{oidc.ScopeOpenID, "profile", "email"}}
}

func (o *OIDC) AuthURL(ctx context.Context, redirect, state, challenge, nonce string, prompt bool) (string, error) {
	p, err := o.discover(ctx)
	if err != nil {
		return "", err
	}
	c := o.config(p, redirect)
	opts := []oauth2.AuthCodeOption{oauth2.SetAuthURLParam("code_challenge", challenge), oauth2.SetAuthURLParam("code_challenge_method", "S256"), oidc.Nonce(nonce)}
	if prompt {
		opts = append(opts, oauth2.SetAuthURLParam("prompt", "login"))
	}
	return c.AuthCodeURL(state, opts...), nil
}

func (o *OIDC) Exchange(ctx context.Context, redirect, code, verifier, nonce string) (*OAuthUserInfo, error) {
	p, err := o.discover(ctx)
	if err != nil {
		return nil, err
	}
	c := o.config(p, redirect)
	token, err := c.Exchange(ctx, code, oauth2.SetAuthURLParam("code_verifier", verifier))
	if err != nil {
		return nil, err
	}
	raw, ok := token.Extra("id_token").(string)
	if !ok {
		return nil, fmt.Errorf("missing id token")
	}
	id, err := p.Verifier(&oidc.Config{ClientID: o.ClientID, SupportedSigningAlgs: []string{oidc.RS256, oidc.ES256, oidc.EdDSA}}).Verify(ctx, raw)
	if err != nil {
		return nil, err
	}
	if id.Nonce != nonce {
		return nil, fmt.Errorf("invalid nonce")
	}
	var claims struct {
		Email         string `json:"email"`
		Name          string `json:"name"`
		EmailVerified bool   `json:"email_verified"`
	}
	if err := id.Claims(&claims); err != nil {
		return nil, err
	}
	if claims.Email == "" {
		// The access token never leaves HTTPS for a plain-HTTP userinfo URL.
		if strings.HasPrefix(o.Issuer, "https://") && !strings.HasPrefix(p.UserInfoEndpoint(), "https://") {
			return nil, fmt.Errorf("userinfo endpoint is not https")
		}
		ui, err := p.UserInfo(ctx, oauth2.StaticTokenSource(token))
		if err != nil {
			return nil, err
		}
		if ui.Subject != id.Subject {
			return nil, fmt.Errorf("userinfo subject mismatch")
		}
		var profile struct {
			Name string `json:"name"`
		}
		if err := ui.Claims(&profile); err != nil {
			return nil, err
		}
		claims.Email, claims.EmailVerified, claims.Name = ui.Email, ui.EmailVerified, profile.Name
	}
	if id.Subject == "" || claims.Email == "" {
		return nil, fmt.Errorf("missing identity")
	}
	return &OAuthUserInfo{Subject: id.Subject, Email: claims.Email, Name: claims.Name, EmailVerified: claims.EmailVerified}, nil
}
