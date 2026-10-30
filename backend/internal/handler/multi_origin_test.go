package handler_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"217/backend/internal/auth"
)

// redirectProvider records the redirect URI used at authorize and exchange time.
type redirectProvider struct {
	fakeOAuthProvider
	authRedirect     string
	exchangeRedirect string
}

func (p *redirectProvider) AuthCodeURLForRedirect(state, challenge, nonce, redirectURI string) string {
	p.authRedirect = redirectURI
	return p.AuthCodeURL(state, challenge, nonce)
}

func (p *redirectProvider) ExchangeWithRedirect(ctx context.Context, code, verifier, redirectURI string) (*auth.OAuthUserInfo, error) {
	p.exchangeRedirect = redirectURI
	return p.Exchange(ctx, code, verifier, p.nonce)
}

func runBrowserLogin(t *testing.T, p *redirectProvider, host string, headers map[string]string) (*httptest.ResponseRecorder, *httptest.ResponseRecorder) {
	t.Helper()
	h, _ := newTestHandler(t)
	h.SetAppBaseURL("https://new.example")
	h.SetAllowedOrigins([]string{"https://new.example", "https://legacy.example"})
	h.SetOAuthProvider(p)

	startReq := httptest.NewRequest(http.MethodGet, "/api/auth/workos", nil)
	startReq.Host = host
	for k, v := range headers {
		startReq.Header.Set(k, v)
	}
	startW := httptest.NewRecorder()
	h.StartWorkOSOAuth(startW, startReq)
	if startW.Code != http.StatusOK {
		t.Fatalf("start: %d %s", startW.Code, startW.Body.String())
	}
	authURL, _ := url.Parse(mustAuthURLFromStart(t, startW))
	binding := cookieNamed(t, startW.Result().Cookies(), "217_oauth_binding")

	cbReq := httptest.NewRequest(http.MethodGet, "/api/auth/workos/callback?code=c&state="+url.QueryEscape(authURL.Query().Get("state")), nil)
	cbReq.Host = host
	cbReq.AddCookie(binding)
	cbW := httptest.NewRecorder()
	h.WorkOSOAuthCallback(cbW, cbReq)
	return startW, cbW
}

func newRedirectProvider() *redirectProvider {
	return &redirectProvider{fakeOAuthProvider: fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{Subject: "s", Email: "u@example.com", EmailVerified: true}}}
}

func TestBrowserLoginUsesRequestOriginForRedirectAndExchange(t *testing.T) {
	for _, tc := range []struct {
		name    string
		host    string
		headers map[string]string
		origin  string
	}{
		{"canonical", "new.example", nil, "https://new.example"},
		{"legacy host", "legacy.example", nil, "https://legacy.example"},
		{"legacy forwarded host", "backend:8080", map[string]string{"X-Forwarded-Host": "Legacy.Example"}, "https://legacy.example"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := newRedirectProvider()
			_, cbW := runBrowserLogin(t, p, tc.host, tc.headers)
			want := tc.origin + "/api/auth/workos/callback"
			if p.authRedirect != want || p.exchangeRedirect != want {
				t.Fatalf("redirect auth=%q exchange=%q, want %q", p.authRedirect, p.exchangeRedirect, want)
			}
			if cbW.Code != http.StatusFound || cbW.Header().Get("Location") != tc.origin {
				t.Fatalf("callback: %d -> %q, want %q", cbW.Code, cbW.Header().Get("Location"), tc.origin)
			}
		})
	}
}

func TestBrowserLoginRejectsUnlistedHost(t *testing.T) {
	for _, tc := range []struct {
		name    string
		host    string
		headers map[string]string
	}{
		{"host header", "evil.example", nil},
		{"forwarded host", "new.example", map[string]string{"X-Forwarded-Host": "evil.example"}},
		{"suffix trick", "legacy.example.evil.example", nil},
		{"scheme-less port", "legacy.example:444", nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := newRedirectProvider()
			_, cbW := runBrowserLogin(t, p, tc.host, tc.headers)
			want := "https://new.example/api/auth/workos/callback"
			if p.authRedirect != want || p.exchangeRedirect != want {
				t.Fatalf("unlisted host must fall back to canonical, auth=%q exchange=%q", p.authRedirect, p.exchangeRedirect)
			}
			if cbW.Header().Get("Location") != "https://new.example" {
				t.Fatalf("redirected to %q", cbW.Header().Get("Location"))
			}
		})
	}
}

func TestSameOriginAllowsEveryListedOrigin(t *testing.T) {
	h, s := newTestHandler(t)
	h.SetAppBaseURL("https://new.example")
	h.SetAllowedOrigins([]string{"https://new.example", "https://legacy.example"})
	user, err := s.CreateUser("a@example.com", "A", "password123")
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)
	for origin, want := range map[string]int{
		"https://new.example":    http.StatusOK,
		"https://legacy.example": http.StatusOK,
		"https://evil.example":   http.StatusForbidden,
	} {
		req := authedRequest(http.MethodPost, "/api/auth/logout", cookie, nil)
		req.Header.Set("Origin", origin)
		w := httptest.NewRecorder()
		h.Logout(w, req)
		if w.Code != want {
			t.Errorf("origin %s: got %d, want %d", origin, w.Code, want)
		}
	}
}
