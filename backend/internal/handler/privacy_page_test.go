package handler_test

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"regexp"
	"strings"
	"testing"

	"217/backend/internal/auth"
	"217/backend/internal/model"
)

var csrfField = regexp.MustCompile(`name="csrf" value="([0-9a-f]+)"`)

func privacyPage(t *testing.T, h interface {
	PrivacyPage(http.ResponseWriter, *http.Request)
}, target string, cookie *http.Cookie, header ...string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, target, nil)
	for i := 0; i+1 < len(header); i += 2 {
		req.Header.Set(header[i], header[i+1])
	}
	if cookie != nil {
		req.AddCookie(cookie)
	}
	w := httptest.NewRecorder()
	h.PrivacyPage(w, req)
	return w
}

func privacyForm(path string, cookie *http.Cookie, form url.Values) *http.Request {
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Origin", "http://localhost:8080")
	if cookie != nil {
		req.AddCookie(cookie)
	}
	return req
}

func TestPrivacyPageLanguageAndSignedOut(t *testing.T) {
	h, _ := newTestHandler(t)
	w := privacyPage(t, h, "/api/privacy", nil, "Accept-Language", "pt-BR,pt;q=0.9,en;q=0.8")
	if w.Code != http.StatusOK || !strings.Contains(w.Header().Get("Content-Type"), "text/html") {
		t.Fatalf("page: %d %q", w.Code, w.Header().Get("Content-Type"))
	}
	body := w.Body.String()
	if !strings.Contains(body, "Aviso de privacidade") || !strings.Contains(body, `lang="pt"`) {
		t.Fatalf("expected Portuguese page from Accept-Language")
	}
	if strings.Contains(body, `name="csrf"`) {
		t.Fatal("signed-out page must not offer the forms")
	}
	if w = privacyPage(t, h, "/api/privacy?lang=es", nil, "Accept-Language", "pt"); !strings.Contains(w.Body.String(), "Aviso de privacidad") {
		t.Fatal("?lang= must win over Accept-Language")
	}
}

func TestPrivacyExportNeedsCSRFAndFreshSignIn(t *testing.T) {
	h, s := newTestHandler(t)
	user, _ := s.LinkWorkOSIdentity("privacy-page-export", "export-page@example.com", "E", true)
	cookie := sessionCookie(t, s, user.ID)
	// The card only opens the warning step; the form lives on that step.
	if page := privacyPage(t, h, "/api/privacy?lang=en", cookie).Body.String(); strings.Contains(page, `action="/api/privacy/export"`) ||
		!strings.Contains(page, "confirm=download") {
		t.Fatal("download must start with its warning step")
	}
	page := privacyPage(t, h, "/api/privacy?lang=en&confirm=download", cookie).Body.String()
	m := csrfField.FindStringSubmatch(page)
	if m == nil || !strings.Contains(page, `action="/api/privacy/export"`) || !strings.Contains(page, "Download your data?") {
		t.Fatalf("fresh session should get the download warning and form")
	}

	w := httptest.NewRecorder()
	h.PrivacyExport(w, privacyForm("/api/privacy/export", cookie, url.Values{"csrf": {"wrong"}}))
	if w.Code != http.StatusForbidden {
		t.Fatalf("bad csrf: %d", w.Code)
	}

	w = httptest.NewRecorder()
	h.PrivacyExport(w, privacyForm("/api/privacy/export", cookie, url.Values{"csrf": {m[1]}}))
	if w.Code != http.StatusOK || !strings.Contains(w.Header().Get("Content-Disposition"), "attachment") ||
		!strings.Contains(w.Body.String(), "export-page@example.com") {
		t.Fatalf("export: %d %q", w.Code, w.Header().Get("Content-Disposition"))
	}
}

// Every action needs a recent sign-in, enforced by the server: a stale
// session gets the warning with a sign-in link (no form), and a post is sent
// through AuthKit back to that warning step without doing anything.
func TestPrivacyActionsNeedFreshSignIn(t *testing.T) {
	h, s := newTestHandler(t)
	user, _ := s.LinkWorkOSIdentity("privacy-page-stale", "stale@example.com", "S", true)
	_, _ = s.RecordConsent(user.ID, model.ConsentVersion)
	cookie := sessionCookie(t, s, user.ID)
	csrf := csrfField.FindStringSubmatch(privacyPage(t, h, "/api/privacy?confirm=delete", cookie).Body.String())[1]
	h.SetReauthWindow(0)
	for action, post := range map[string]func(http.ResponseWriter, *http.Request){
		"download": h.PrivacyExport, "withdraw": h.PrivacyWithdraw, "delete": h.PrivacyDelete,
	} {
		page := privacyPage(t, h, "/api/privacy?lang=pt&confirm="+action, cookie).Body.String()
		if strings.Contains(page, `method="post"`) || !strings.Contains(page, "/api/privacy/signin?confirm="+action+"&amp;lang=pt") {
			t.Fatalf("%s: stale session must get a sign-in link, not the form", action)
		}
		w := httptest.NewRecorder()
		post(w, privacyForm("/api/privacy/"+action, cookie, url.Values{"csrf": {csrf}, "lang": {"pt"}}))
		if w.Code != http.StatusSeeOther || w.Header().Get("Location") != "/api/privacy/signin?confirm="+action+"&lang=pt" {
			t.Fatalf("stale %s: %d %q", action, w.Code, w.Header().Get("Location"))
		}
	}
	if u, err := s.GetUserByID(user.ID); err != nil || !u.HasConsent() {
		t.Fatalf("stale posts must not change anything: %+v %v", u, err)
	}
}

func TestPrivacyWithdrawAndDelete(t *testing.T) {
	h, s := newTestHandler(t)
	user, _ := s.LinkWorkOSIdentity("privacy-page-del", "del-page@example.com", "D", true)
	if _, err := s.RecordConsent(user.ID, model.ConsentVersion); err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)
	m := csrfField.FindStringSubmatch(privacyPage(t, h, "/api/privacy?confirm=withdraw", cookie).Body.String())
	if m == nil {
		t.Fatal("no csrf token")
	}

	w := httptest.NewRecorder()
	h.PrivacyWithdraw(w, privacyForm("/api/privacy/withdraw", cookie, url.Values{"csrf": {m[1]}, "lang": {"es"}}))
	if w.Code != http.StatusSeeOther || w.Header().Get("Location") != "/api/privacy?done=withdrawn&lang=es" {
		t.Fatalf("withdraw: %d %q", w.Code, w.Header().Get("Location"))
	}
	if u, _ := s.GetUserByID(user.ID); u.HasConsent() || u.ConsentedAt != nil {
		t.Fatalf("consent not withdrawn: %+v", u)
	}

	cross := privacyForm("/api/privacy/delete", cookie, url.Values{"csrf": {m[1]}})
	cross.Header.Set("Origin", "https://evil.example")
	w = httptest.NewRecorder()
	h.PrivacyDelete(w, cross)
	if w.Code != http.StatusForbidden {
		t.Fatalf("cross-origin delete: %d", w.Code)
	}

	w = httptest.NewRecorder()
	h.PrivacyDelete(w, privacyForm("/api/privacy/delete", cookie, url.Values{"csrf": {m[1]}}))
	if w.Code != http.StatusSeeOther || !strings.Contains(w.Header().Get("Location"), "done=deleted") {
		t.Fatalf("delete: %d %q", w.Code, w.Header().Get("Location"))
	}
	if _, err := s.GetUserByID(user.ID); err == nil {
		t.Fatal("user still exists")
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

func TestPrivacySignInReturnsToPage(t *testing.T) {
	h, _ := newTestHandler(t)
	provider := &fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{Subject: "page-subject", Email: "page@example.com", EmailVerified: true}}
	h.SetOAuthProvider(provider)
	w := httptest.NewRecorder()
	h.PrivacySignIn(w, httptest.NewRequest(http.MethodGet, "/api/privacy/signin?lang=pt&confirm=delete", nil))
	if w.Code != http.StatusSeeOther || !strings.HasPrefix(w.Header().Get("Location"), "https://api.workos.com/") {
		t.Fatalf("signin: %d %q", w.Code, w.Header().Get("Location"))
	}
	cb := httptest.NewRequest(http.MethodGet, "/api/auth/workos/callback?code=c&state="+url.QueryEscape(provider.state), nil)
	cb.AddCookie(cookieNamed(t, w.Result().Cookies(), "217_oauth_binding"))
	cb.AddCookie(cookieNamed(t, w.Result().Cookies(), "217_oauth_return"))
	w = httptest.NewRecorder()
	h.WorkOSOAuthCallback(w, cb)
	if w.Code != http.StatusFound || w.Header().Get("Location") != "http://localhost:8080/api/privacy?confirm=delete&lang=pt" {
		t.Fatalf("callback: %d %q", w.Code, w.Header().Get("Location"))
	}

	// A forged return cookie never leaves the privacy page.
	w = httptest.NewRecorder()
	h.PrivacySignIn(w, httptest.NewRequest(http.MethodGet, "/api/privacy/signin", nil))
	cb = httptest.NewRequest(http.MethodGet, "/api/auth/workos/callback?code=c&state="+url.QueryEscape(provider.state), nil)
	cb.AddCookie(cookieNamed(t, w.Result().Cookies(), "217_oauth_binding"))
	cb.AddCookie(&http.Cookie{Name: "217_oauth_return", Value: url.QueryEscape("//evil.example/x")})
	w = httptest.NewRecorder()
	h.WorkOSOAuthCallback(w, cb)
	if loc := w.Header().Get("Location"); loc != "http://localhost:8080" {
		t.Fatalf("forged return: %q", loc)
	}
}
