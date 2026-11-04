package handler_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"217/backend/internal/auth"
	"217/backend/internal/handler"
	"217/backend/internal/model"
	"217/backend/internal/store"
)

func TestReturnCookieAttributes(t *testing.T) {
	h, _ := newTestHandler(t)
	h.SetOAuthProvider(&fakeOAuthProvider{})
	w := httptest.NewRecorder()
	h.StartWorkOSOAuth(w, httptest.NewRequest(http.MethodGet, "/api/auth/workos?return="+url.QueryEscape("/app/privacy?lang=pt"), nil))
	c := returnCookie(w.Result().Cookies())
	if c == nil {
		t.Fatal("no return cookie")
	}
	if c.Path != auth.BrowserCallbackPath || !c.HttpOnly || c.SameSite != http.SameSiteLaxMode || c.MaxAge != 300 {
		t.Fatalf("cookie attributes: %+v", c)
	}
}

func TestCookieDeleteNeedsSameOrigin(t *testing.T) {
	h, s := newTestHandler(t)
	user, _ := s.LinkWorkOSIdentity("csrf-subject", "csrf@example.com", "C", true)
	cookie := sessionCookie(t, s, user.ID)
	guarded := h.AuthMiddleware(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNoContent) })
	for origin, want := range map[string]int{"": 403, "http://evil.example": 403, "http://localhost:8080": 204} {
		req := authedRequest(http.MethodDelete, "/api/account", cookie, nil)
		req.Header.Del("Origin")
		if origin != "" {
			req.Header.Set("Origin", origin)
		}
		w := httptest.NewRecorder()
		guarded(w, req)
		if w.Code != want {
			t.Errorf("origin %q: %d, want %d", origin, w.Code, want)
		}
	}
}

func TestCookieRequestsFailClosedWithoutAppOrigin(t *testing.T) {
	s := store.NewMemoryStore()
	h := handler.New(s)
	user, _ := s.LinkWorkOSIdentity("closed-subject", "closed@example.com", "C", true)
	cookie := sessionCookie(t, s, user.ID)
	guarded := h.AuthMiddleware(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNoContent) })
	w := httptest.NewRecorder()
	guarded(w, authedRequest(http.MethodDelete, "/api/account", cookie, nil))
	if w.Code != http.StatusForbidden {
		t.Fatalf("cookie without app origin: %d", w.Code)
	}
	bearer := httptest.NewRequest(http.MethodDelete, "/api/account", nil)
	bearer.Header.Set("Authorization", "Bearer "+cookie.Value)
	w = httptest.NewRecorder()
	guarded(w, bearer)
	if w.Code != http.StatusNoContent {
		t.Fatalf("bearer without app origin: %d", w.Code)
	}
}

func TestLegacyPrivacyPageRedirectsToApp(t *testing.T) {
	h, _ := newTestHandler(t)
	for target, want := range map[string]string{
		"/api/privacy":         "/app/privacy",
		"/api/privacy?lang=pt": "/app/privacy?lang=pt",
		"/api/privacy/signin?lang=es&confirm=delete":  "/app/privacy?confirm=delete&lang=es",
		"/api/privacy?lang=xx&confirm=evil&next=//ev": "/app/privacy",
	} {
		w := httptest.NewRecorder()
		h.LegacyPrivacyPage(w, httptest.NewRequest(http.MethodGet, target, nil))
		if w.Code != http.StatusFound || w.Header().Get("Location") != want {
			t.Errorf("%s: %d -> %q, want %q", target, w.Code, w.Header().Get("Location"), want)
		}
	}
}

func TestSignInReturnsToPrivacyPages(t *testing.T) {
	h, _ := newTestHandler(t)
	provider := &fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{Subject: "page-subject", Email: "page@example.com", EmailVerified: true}}
	h.SetOAuthProvider(provider)
	login := func(returnTo string, forged *http.Cookie) string {
		t.Helper()
		w := httptest.NewRecorder()
		h.StartWorkOSOAuth(w, httptest.NewRequest(http.MethodGet, "/api/auth/workos?return="+url.QueryEscape(returnTo), nil))
		if w.Code != http.StatusOK {
			t.Fatalf("start: %d %s", w.Code, w.Body.String())
		}
		cb := httptest.NewRequest(http.MethodGet, "/api/auth/workos/callback?code=c&state="+url.QueryEscape(provider.state), nil)
		cb.AddCookie(cookieNamed(t, w.Result().Cookies(), "217_oauth_binding"))
		if forged != nil {
			cb.AddCookie(forged)
		} else if ret := returnCookie(w.Result().Cookies()); ret != nil {
			cb.AddCookie(ret)
		}
		w = httptest.NewRecorder()
		h.WorkOSOAuthCallback(w, cb)
		if w.Code != http.StatusFound {
			t.Fatalf("callback: %d %s", w.Code, w.Body.String())
		}
		return w.Header().Get("Location")
	}
	for returnTo, want := range map[string]string{
		"":                                    "http://localhost:8080/app/",
		"/app/privacy?lang=pt&confirm=delete": "http://localhost:8080/app/privacy?confirm=delete&lang=pt",
		"/app/privacy?lang=pt&x=1&confirm=ev": "http://localhost:8080/app/privacy?lang=pt",
		"/app/account/delete?lang=es":         "http://localhost:8080/app/account/delete?lang=es",
		"/app/privacy/../x":                   "http://localhost:8080/app/",
		"/app/privacy%2F%2Fx":                 "http://localhost:8080/app/",
		"/app/privacy#frag":                   "http://localhost:8080/app/",
		"/app/privacy\\x":                     "http://localhost:8080/app/",
		"//evil.example/app/privacy":          "http://localhost:8080/app/",
		"/app/privacy-evil":                   "http://localhost:8080/app/",
		"/api/privacy":                        "http://localhost:8080/app/",
	} {
		if got := login(returnTo, nil); got != want {
			t.Errorf("return %q: landed on %q, want %q", returnTo, got, want)
		}
	}
	// A forged return cookie never leaves the privacy pages.
	forged := &http.Cookie{Name: "217_oauth_return", Value: url.QueryEscape("//evil.example/x")}
	if got := login("", forged); got != "http://localhost:8080/app/" {
		t.Fatalf("forged return: %q", got)
	}
}

func returnCookie(cookies []*http.Cookie) *http.Cookie {
	for _, c := range cookies {
		if c.Name == "217_oauth_return" && c.MaxAge > 0 {
			return c
		}
	}
	return nil
}

func TestSessionReportsRecentSignIn(t *testing.T) {
	h, s := newTestHandler(t)
	user, _ := s.LinkWorkOSIdentity("fresh-subject", "fresh@example.com", "F", true)
	cookie := sessionCookie(t, s, user.ID)
	recent := func() any {
		w := httptest.NewRecorder()
		h.CurrentSession(w, authedRequest(http.MethodGet, "/api/auth/session", cookie, nil))
		var body map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
			t.Fatalf("session: %v", err)
		}
		return body["recent_sign_in"]
	}
	if got := recent(); got != true {
		t.Fatalf("new session: recent_sign_in = %v", got)
	}
	h.SetReauthWindow(time.Nanosecond)
	time.Sleep(time.Millisecond)
	if got := recent(); got != false {
		t.Fatalf("old session: recent_sign_in = %v", got)
	}
}

func TestBrowserActionsNeedRecentSignIn(t *testing.T) {
	h, s := newTestHandler(t)
	user, _ := s.LinkWorkOSIdentity("stale-subject", "stale@example.com", "S", true)
	cookie := sessionCookie(t, s, user.ID)
	reached := 0
	guarded := h.AuthMiddleware(h.RecentBrowserSignIn(func(w http.ResponseWriter, r *http.Request) {
		reached++
		w.WriteHeader(http.StatusNoContent)
	}))
	call := func(req *http.Request) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		guarded(w, req)
		return w
	}
	if w := call(authedRequest(http.MethodDelete, "/api/account", cookie, nil)); w.Code != http.StatusNoContent {
		t.Fatalf("fresh cookie: %d %s", w.Code, w.Body.String())
	}
	h.SetReauthWindow(time.Nanosecond)
	time.Sleep(time.Millisecond)
	if w := call(authedRequest(http.MethodDelete, "/api/account", cookie, nil)); w.Code != http.StatusForbidden || !strings.Contains(w.Body.String(), "reauth required") {
		t.Fatalf("stale cookie: %d %s", w.Code, w.Body.String())
	}
	// Apps (Bearer) are not asked: they renew sessions with the device key.
	bearer := httptest.NewRequest(http.MethodDelete, "/api/account", nil)
	bearer.Header.Set("Authorization", "Bearer "+cookie.Value)
	if w := call(bearer); w.Code != http.StatusNoContent {
		t.Fatalf("bearer: %d %s", w.Code, w.Body.String())
	}
	if reached != 2 {
		t.Fatalf("handler reached %d times, want 2", reached)
	}
}

func TestWithdrawConsentEndpoint(t *testing.T) {
	h, s := newTestHandler(t)
	user, _ := s.LinkWorkOSIdentity("withdraw-api", "withdraw@example.com", "W", true)
	_, _ = s.RecordConsent(user.ID, model.ConsentVersion)
	_, _ = s.SetRole(user.ID, model.RoleOwner)
	cookie := sessionCookie(t, s, user.ID)
	w := httptest.NewRecorder()
	h.AuthMiddleware(h.WithdrawConsent)(w, authedRequest(http.MethodDelete, "/api/account/consent", cookie, nil))
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"required":true`) {
		t.Fatalf("withdraw: %d %s", w.Code, w.Body.String())
	}
	w = httptest.NewRecorder()
	h.ConsentMiddleware(h.ListEntries)(w, authedRequest(http.MethodGet, "/api/entries", cookie, nil))
	if w.Code != http.StatusForbidden || !strings.Contains(w.Body.String(), "consent required") {
		t.Fatalf("after withdraw: %d %s", w.Code, w.Body.String())
	}
}
