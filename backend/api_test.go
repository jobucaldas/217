package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"217/backend/internal/auth"
	"217/backend/internal/handler"
	"217/backend/internal/model"
	"217/backend/internal/store"
)

type fakeOAuthProvider struct {
	nonce          string
	exchangeNonce  string
	state          string
	challenge      string
	exchangeCode   string
	exchangeVerify string
	userInfo       *auth.OAuthUserInfo
	exchangeErr    error
}

func (f *fakeOAuthProvider) AuthCodeURL(state, codeChallenge, nonce string) string {
	f.nonce = nonce
	f.state = state
	f.challenge = codeChallenge
	return "https://accounts.google.com/o/oauth2/v2/auth?state=" + url.QueryEscape(state) + "&code_challenge=" + url.QueryEscape(codeChallenge) + "&code_challenge_method=S256"
}

func (f *fakeOAuthProvider) Exchange(_ context.Context, code, codeVerifier, nonce string) (*auth.OAuthUserInfo, error) {
	f.exchangeNonce = nonce
	if nonce != f.nonce || nonce == "" {
		return nil, fmt.Errorf("nonce mismatch")
	}
	f.exchangeCode = code
	f.exchangeVerify = codeVerifier
	if f.exchangeErr != nil {
		return nil, f.exchangeErr
	}
	return f.userInfo, nil
}

func newTestHandler(t *testing.T) (*handler.Handler, *store.MemoryStore) {
	t.Helper()
	s := store.NewMemoryStore()
	h := handler.New(s)
	h.SetAppBaseURL("http://localhost:8080")
	return h, s
}

func sessionCookie(t *testing.T, s *store.MemoryStore, userID string) *http.Cookie {
	t.Helper()
	token := "session-token-" + userID
	if err := s.CreateSession(userID, token, time.Now().Add(time.Hour), "test-agent", "127.0.0.1"); err != nil {
		t.Fatalf("create session: %v", err)
	}
	return &http.Cookie{Name: "217_session", Value: token}
}

func authedRequest(method, path string, cookie *http.Cookie, body []byte) *http.Request {
	req := httptest.NewRequest(method, path, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if cookie != nil {
		req.AddCookie(cookie)
	}
	return req
}

func TestGoogleOAuthStartAndCallback(t *testing.T) {
	h, s := newTestHandler(t)
	user, err := s.CreateUser("verified@example.com", "Verified User", "password123")
	if err != nil {
		t.Fatal(err)
	}
	provider := &fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{Subject: "google-subject-1", Email: "verified@example.com", EmailVerified: true, HostedDomain: "example.com", Name: "Google User"}}
	h.SetOAuthProvider(provider)

	startReq := httptest.NewRequest(http.MethodGet, "/api/auth/google", nil)
	startW := httptest.NewRecorder()
	h.StartGoogleOAuth(startW, startReq)
	if startW.Code != http.StatusFound {
		t.Fatalf("expected redirect, got %d: %s", startW.Code, startW.Body.String())
	}
	location := startW.Header().Get("Location")
	parsed, err := url.Parse(location)
	if err != nil {
		t.Fatalf("parse redirect url: %v", err)
	}
	state := parsed.Query().Get("state")
	bindingCookie := cookieNamed(t, startW.Result().Cookies(), "217_oauth_binding")
	challenge := parsed.Query().Get("code_challenge")
	if state == "" || challenge == "" {
		t.Fatalf("missing state or challenge in redirect: %s", location)
	}
	if parsed.Query().Get("code_challenge_method") != "S256" {
		t.Fatalf("expected S256 PKCE, got %s", parsed.RawQuery)
	}
	if provider.state != state {
		t.Fatalf("provider saw unexpected state: %q vs %q", provider.state, state)
	}
	if provider.challenge != challenge {
		t.Fatalf("provider saw unexpected challenge: %q vs %q", provider.challenge, challenge)
	}

	cbReq := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=auth-code&state="+url.QueryEscape(state), nil)
	cbReq.AddCookie(bindingCookie)
	cbW := httptest.NewRecorder()
	h.GoogleOAuthCallback(cbW, cbReq)
	if cbW.Code != http.StatusFound {
		t.Fatalf("expected callback redirect, got %d: %s", cbW.Code, cbW.Body.String())
	}
	if provider.exchangeCode != "auth-code" {
		t.Fatalf("unexpected exchange code %q", provider.exchangeCode)
	}
	if provider.exchangeNonce != provider.nonce || provider.nonce == state || provider.nonce == provider.exchangeVerify || provider.nonce == bindingCookie.Value {
		t.Fatal("nonce must be independent and round-trip with the attempt")
	}
	if provider.exchangeVerify == "" {
		t.Fatal("expected PKCE verifier to be used")
	}
	cookie := cookieNamed(t, cbW.Result().Cookies(), "217_session")
	if !cookie.HttpOnly || cookie.SameSite != http.SameSiteLaxMode || cookie.Path != "/" || cookie.Secure || cookie.MaxAge <= 0 {
		t.Fatalf("unexpected localhost session cookie flags: %#v", cookie)
	}
	currentReq := authedRequest(http.MethodGet, "/api/auth/session", cookie, nil)
	currentW := httptest.NewRecorder()
	h.CurrentSession(currentW, currentReq)
	if currentW.Code != http.StatusOK {
		t.Fatalf("current session failed: %d", currentW.Code)
	}
	var current map[string]any
	if err := json.NewDecoder(currentW.Body).Decode(&current); err != nil {
		t.Fatal(err)
	}
	userMap, ok := current["user"].(map[string]any)
	if !ok {
		t.Fatalf("expected user in current session: %#v", current)
	}
	if userMap["email"] != user.Email {
		t.Fatalf("expected linked user email %s, got %#v", user.Email, userMap)
	}
	if _, ok := userMap["api_key"]; ok {
		t.Fatal("session response must not expose api_key")
	}

	reuseReq := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=auth-code&state="+url.QueryEscape(state), nil)
	reuseReq.AddCookie(bindingCookie)
	reuseW := httptest.NewRecorder()
	h.GoogleOAuthCallback(reuseW, reuseReq)
	if reuseW.Code != http.StatusBadRequest {
		t.Fatalf("reused state should fail, got %d", reuseW.Code)
	}
}

func TestGoogleOAuthCallbackRejectsUnknownState(t *testing.T) {
	h, _ := newTestHandler(t)
	h.SetOAuthProvider(&fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{Subject: "subject", Email: "user@example.com", EmailVerified: true}})
	w := httptest.NewRecorder()
	h.GoogleOAuthCallback(w, httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=code&state=unknown", nil))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("unknown state should fail, got %d", w.Code)
	}
}

func TestHTTPSUsesSecureSessionCookie(t *testing.T) {
	h, _ := newTestHandler(t)
	h.SetAppBaseURL("https://app.example")
	provider := &fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{Subject: "new-subject", Email: "new@example.com", EmailVerified: true, Name: "New User"}}
	h.SetOAuthProvider(provider)
	state, bindingCookie := startOAuth(t, h)
	w := httptest.NewRecorder()
	callback := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=code&state="+url.QueryEscape(state), nil)
	callback.AddCookie(bindingCookie)
	h.GoogleOAuthCallback(w, callback)
	cookies := w.Result().Cookies()
	if w.Code != http.StatusFound || !cookieNamed(t, cookies, "217_session").Secure || !cookieNamed(t, cookies, "217_oauth_binding").Secure {
		t.Fatalf("HTTPS callback must use Secure cookies: status=%d cookies=%#v", w.Code, cookies)
	}
}

func TestGoogleOAuthCallbackRejectsUnverifiedEmail(t *testing.T) {
	h, _ := newTestHandler(t)
	provider := &fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{Subject: "google-subject-2", Email: "verified@example.com", EmailVerified: false, Name: "Google User"}}
	h.SetOAuthProvider(provider)

	startReq := httptest.NewRequest(http.MethodGet, "/api/auth/google", nil)
	startW := httptest.NewRecorder()
	h.StartGoogleOAuth(startW, startReq)
	state := mustStateFromLocation(t, startW.Header().Get("Location"))
	bindingCookie := cookieNamed(t, startW.Result().Cookies(), "217_oauth_binding")

	cbReq := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=auth-code&state="+url.QueryEscape(state), nil)
	cbReq.AddCookie(bindingCookie)
	cbW := httptest.NewRecorder()
	h.GoogleOAuthCallback(cbW, cbReq)
	if cbW.Code != http.StatusForbidden {
		t.Fatalf("expected forbidden, got %d", cbW.Code)
	}
}

func TestGoogleOAuthCallbackRequiresBrowserBindingAndClearsCookie(t *testing.T) {
	h, _ := newTestHandler(t)
	h.SetOAuthProvider(&fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{Subject: "subject", Email: "user@example.com", EmailVerified: true}})
	state, _ := startOAuth(t, h)
	w := httptest.NewRecorder()
	h.GoogleOAuthCallback(w, httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=code&state="+url.QueryEscape(state), nil))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("missing browser binding should fail, got %d", w.Code)
	}
	cleared := cookieNamed(t, w.Result().Cookies(), "217_oauth_binding")
	if cleared.MaxAge != -1 || cleared.Path != "/api/auth/google/callback" {
		t.Fatalf("callback must clear scoped binding cookie: %#v", cleared)
	}
}

func TestGoogleOAuthCallbackLinksByNormalizedEmailAndSubject(t *testing.T) {
	h, s := newTestHandler(t)
	user, err := s.CreateUser("Linked@Example.com", "Linked User", "password123")
	if err != nil {
		t.Fatal(err)
	}

	providerA := &fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{Subject: "subject-a", Email: "linked@example.com", EmailVerified: true, HostedDomain: "example.com", Name: "Google User"}}
	h.SetOAuthProvider(providerA)
	stateA, bindingA := startOAuth(t, h)
	cbA := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=code-a&state="+url.QueryEscape(stateA), nil)
	cbA.AddCookie(bindingA)
	cbWA := httptest.NewRecorder()
	h.GoogleOAuthCallback(cbWA, cbA)
	if cbWA.Code != http.StatusFound {
		t.Fatalf("expected successful first link, got %d", cbWA.Code)
	}

	providerB := &fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{Subject: "subject-b", Email: "linked@example.com", EmailVerified: true, HostedDomain: "example.com", Name: "Google User"}}
	h.SetOAuthProvider(providerB)
	stateB, bindingB := startOAuth(t, h)
	cbB := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=code-b&state="+url.QueryEscape(stateB), nil)
	cbB.AddCookie(bindingB)
	cbWB := httptest.NewRecorder()
	h.GoogleOAuthCallback(cbWB, cbB)
	if cbWB.Code != http.StatusForbidden {
		t.Fatalf("expected second subject to be rejected, got %d", cbWB.Code)
	}

	providerC := &fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{Subject: "subject-a", Email: "different@example.com", EmailVerified: true, HostedDomain: "example.com", Name: "Google User"}}
	h.SetOAuthProvider(providerC)
	stateC, bindingC := startOAuth(t, h)
	cbC := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=code-c&state="+url.QueryEscape(stateC), nil)
	cbC.AddCookie(bindingC)
	cbWC := httptest.NewRecorder()
	h.GoogleOAuthCallback(cbWC, cbC)
	if cbWC.Code != http.StatusFound {
		t.Fatalf("expected durable subject login, got %d", cbWC.Code)
	}
	cookie := cookieNamed(t, cbWC.Result().Cookies(), "217_session")
	currentReq := authedRequest(http.MethodGet, "/api/auth/session", cookie, nil)
	currentW := httptest.NewRecorder()
	h.CurrentSession(currentW, currentReq)
	var current map[string]any
	if err := json.NewDecoder(currentW.Body).Decode(&current); err != nil {
		t.Fatal(err)
	}
	userMap := current["user"].(map[string]any)
	if userMap["email"] != user.Email {
		t.Fatalf("expected linked user email %s, got %#v", user.Email, userMap)
	}
}

func TestSessionCookieAuthExpiryAndLogout(t *testing.T) {
	h, s := newTestHandler(t)
	user, err := s.CreateUser("session@example.com", "Session User", "password123")
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)

	listReq := authedRequest(http.MethodGet, "/api/entries?year=2026&month=1", cookie, nil)
	listW := httptest.NewRecorder()
	h.AuthMiddleware(h.ListEntries)(listW, listReq)
	if listW.Code != http.StatusOK {
		t.Fatalf("expected session cookie auth, got %d", listW.Code)
	}

	expiredToken := "expired-session"
	if err := s.CreateSession(user.ID, expiredToken, time.Now().Add(-time.Minute), "test-agent", "127.0.0.1"); err != nil {
		t.Fatal(err)
	}
	expiredReq := authedRequest(http.MethodGet, "/api/auth/session", &http.Cookie{Name: "217_session", Value: expiredToken}, nil)
	expiredW := httptest.NewRecorder()
	h.CurrentSession(expiredW, expiredReq)
	var expired map[string]any
	if err := json.NewDecoder(expiredW.Body).Decode(&expired); err != nil {
		t.Fatal(err)
	}
	if expired["user"] != nil {
		t.Fatalf("expected expired session to be cleared, got %#v", expired)
	}
	if got := expiredW.Header().Values("Set-Cookie"); len(got) == 0 {
		t.Fatal("expected expired session cookie to be cleared")
	}

	logoutReq := authedRequest(http.MethodPost, "/api/auth/logout", cookie, nil)
	logoutReq.Header.Set("Origin", "http://localhost:8080")
	logoutW := httptest.NewRecorder()
	h.Logout(logoutW, logoutReq)
	if logoutW.Code != http.StatusOK {
		t.Fatalf("logout failed: %d", logoutW.Code)
	}
	if len(logoutW.Header().Values("Set-Cookie")) == 0 {
		t.Fatal("expected logout to clear the session cookie")
	}

	postLogoutReq := authedRequest(http.MethodGet, "/api/entries?year=2026&month=1", cookie, nil)
	postLogoutW := httptest.NewRecorder()
	h.AuthMiddleware(h.ListEntries)(postLogoutW, postLogoutReq)
	if postLogoutW.Code != http.StatusUnauthorized {
		t.Fatalf("expected logged out session to be rejected, got %d", postLogoutW.Code)
	}
}

func TestOriginGuardRejectsUnsafeCrossOriginRequests(t *testing.T) {
	h, s := newTestHandler(t)
	user, err := s.CreateUser("origin@example.com", "Origin User", "password123")
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)
	body := []byte(`{"taken":true,"notes":""}`)
	req := authedRequest(http.MethodPost, "/api/entries/2026-05-13", cookie, body)
	req.SetPathValue("date", "2026-05-13")
	req.Header.Set("Origin", "https://evil.example")
	w := httptest.NewRecorder()
	h.AuthMiddleware(h.UpsertEntry)(w, req)
	if w.Code != http.StatusForbidden {
		t.Fatalf("expected origin guard to reject cross-site write, got %d", w.Code)
	}
}

func startOAuth(t *testing.T, h *handler.Handler) (string, *http.Cookie) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/auth/google", nil)
	w := httptest.NewRecorder()
	h.StartGoogleOAuth(w, req)
	return mustStateFromLocation(t, w.Header().Get("Location")), cookieNamed(t, w.Result().Cookies(), "217_oauth_binding")
}

func cookieNamed(t *testing.T, cookies []*http.Cookie, name string) *http.Cookie {
	t.Helper()
	for _, cookie := range cookies {
		if cookie.Name == name {
			return cookie
		}
	}
	t.Fatalf("missing cookie %q in %#v", name, cookies)
	return nil
}

func mustStateFromLocation(t *testing.T, location string) string {
	t.Helper()
	parsed, err := url.Parse(location)
	if err != nil {
		t.Fatal(err)
	}
	state := parsed.Query().Get("state")
	if state == "" {
		t.Fatalf("missing state in redirect: %s", location)
	}
	return state
}

func TestProtectedRoutesStillTrackEntriesWithCookieAuth(t *testing.T) {
	h, s := newTestHandler(t)
	user, err := s.CreateUser("entries@example.com", "Entries User", "password123")
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)

	upsertBody := `{"taken":true,"notes":"testado"}`
	req := authedRequest(http.MethodPost, "/api/entries/2026-05-13", cookie, []byte(upsertBody))
	req.SetPathValue("date", "2026-05-13")
	w := httptest.NewRecorder()
	h.AuthMiddleware(h.UpsertEntry)(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected upsert success, got %d: %s", w.Code, w.Body.String())
	}

	getReq := authedRequest(http.MethodGet, "/api/entries/2026-05-13", cookie, nil)
	getReq.SetPathValue("date", "2026-05-13")
	getW := httptest.NewRecorder()
	h.AuthMiddleware(h.GetEntry)(getW, getReq)
	if getW.Code != http.StatusOK {
		t.Fatalf("expected get success, got %d", getW.Code)
	}
	var entry model.Entry
	if err := json.NewDecoder(getW.Body).Decode(&entry); err != nil {
		t.Fatal(err)
	}
	if entry.Notes != "testado" {
		t.Fatalf("expected notes to round-trip, got %#v", entry)
	}
}

func TestGoogleExternalEmailCollisionFailsClosed(t *testing.T) {
	h, s := newTestHandler(t)
	if _, err := s.CreateUser("Legacy@example.com", "Legacy", "password123"); err != nil {
		t.Fatal(err)
	}
	h.SetOAuthProvider(&fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{
		Subject: "external-subject", Email: "legacy@example.com", EmailVerified: true,
	}})
	state, binding := startOAuth(t, h)
	req := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=code&state="+url.QueryEscape(state), nil)
	req.AddCookie(binding)
	w := httptest.NewRecorder()
	h.GoogleOAuthCallback(w, req)
	if w.Code != http.StatusForbidden || !bytes.Contains(w.Body.Bytes(), []byte("Contact the app operator")) {
		t.Fatalf("expected actionable generic rejection, got %d: %s", w.Code, w.Body.String())
	}
	for _, cookie := range w.Result().Cookies() {
		if cookie.Name == "217_session" && cookie.Value != "" {
			t.Fatal("rejected collision issued an app session")
		}
	}
	if _, err := s.ConsumeOAuthAttempt(state, binding.Value); err == nil {
		t.Fatal("rejected callback left its attempt reusable")
	}
}
