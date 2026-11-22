package handler

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"217/backend/internal/auth"
	"217/backend/internal/store"
	"github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"
)

func TestOIDCCallbackInvalidStateAndDiscoveryFailure(t *testing.T) {
	s := store.NewMemoryStore()
	h := New(s)
	h.SetOIDC(&auth.OIDC{Issuer: "http://127.0.0.1:1", ClientID: "client"})
	r := httptest.NewRequest("GET", "/api/auth/oidc/callback?code=code&state=missing", nil)
	w := httptest.NewRecorder()
	h.OIDCCallback(w, r)
	if w.Code != 400 {
		t.Fatalf("invalid state: %d", w.Code)
	}
	if err := s.CreateOAuthAttempt("state", "binding", `{"Kind":"web","Verifier":"verifier"}`, "nonce", "https://app.example.com/api/auth/oidc/callback", time.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	r = httptest.NewRequest("GET", "/api/auth/oidc/callback?code=code&state=state", nil)
	r.AddCookie(&http.Cookie{Name: oauthBindingCookie, Value: "binding"})
	w = httptest.NewRecorder()
	h.OIDCCallback(w, r)
	if w.Code != 503 {
		t.Fatalf("discovery failure: %d", w.Code)
	}
}

func TestOIDCBrowserAndNative(t *testing.T) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	var issuer, nonce, challenge string
	var verified, failExchange bool
	subject, email := "subject", "oidc@example.com"
	mux := http.NewServeMux()
	srv := httptest.NewServer(mux)
	defer srv.Close()
	issuer = srv.URL
	mux.HandleFunc("/.well-known/openid-configuration", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{"issuer": issuer, "authorization_endpoint": issuer + "/authorize", "token_endpoint": issuer + "/token", "jwks_uri": issuer + "/jwks", "id_token_signing_alg_values_supported": []string{"EdDSA"}})
	})
	mux.HandleFunc("/jwks", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(jose.JSONWebKeySet{Keys: []jose.JSONWebKey{{Key: pub, KeyID: "test", Algorithm: "EdDSA", Use: "sig"}}})
	})
	mux.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		if failExchange {
			http.Error(w, "exchange failed", 400)
			return
		}
		id, secret, ok := r.BasicAuth()
		if !ok || id != "client" || secret != "secret" {
			t.Error("basic auth missing")
			http.Error(w, "bad auth", 401)
			return
		}
		r.ParseForm()
		if pkceChallengeS256(r.Form.Get("code_verifier")) != challenge {
			t.Error("bad pkce")
			http.Error(w, "bad pkce", 400)
			return
		}
		signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.EdDSA, Key: jose.JSONWebKey{Key: priv, KeyID: "test"}}, nil)
		if err != nil {
			t.Error(err)
			return
		}
		claims := map[string]any{"iss": issuer, "sub": subject, "aud": "client", "exp": time.Now().Add(time.Minute).Unix(), "iat": time.Now().Unix(), "nonce": nonce, "email": email, "email_verified": verified}
		raw, err := jwt.Signed(signer).Claims(claims).Serialize()
		if err != nil {
			t.Error(err)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"access_token":"x","token_type":"Bearer","id_token":%q}`, raw)
	})
	s := store.NewMemoryStore()
	h := New(s)
	h.SetAppBaseURL("https://app.example.com")
	h.SetOIDC(&auth.OIDC{Issuer: issuer, ClientID: "client", ClientSecret: "secret"})
	start := func(native bool, appChallenge string) (*http.Cookie, string) {
		t.Helper()
		path := "/api/auth/oidc"
		if native {
			path += "/native?app_challenge=" + appChallenge
		}
		r := httptest.NewRequest("GET", "https://app.example.com"+path, nil)
		w := httptest.NewRecorder()
		if native {
			h.StartOIDCNative(w, r)
		} else {
			h.StartOIDC(w, r)
		}
		var u string
		if native {
			u = w.Header().Get("Location")
		} else {
			var b map[string]string
			json.Unmarshal(w.Body.Bytes(), &b)
			u = b["auth_url"]
		}
		parsed, err := url.Parse(u)
		if err != nil || parsed.Host == "" {
			t.Fatalf("start status=%d body=%s", w.Code, w.Body.String())
		}
		q := parsed.Query()
		nonce = q.Get("nonce")
		challenge = q.Get("code_challenge")
		if q.Get("code_challenge_method") != "S256" {
			t.Fatal("missing pkce")
		}
		if c := w.Result().Cookies()[0]; c.Path != oidcCallbackPath {
			t.Fatalf("binding cookie path %q never reaches the callback", c.Path)
		}
		return w.Result().Cookies()[0], q.Get("state")
	}
	callback := func(cookie *http.Cookie, state string) *httptest.ResponseRecorder {
		t.Helper()
		r := httptest.NewRequest("GET", "https://app.example.com/api/auth/oidc/callback?code=provider-code&state="+url.QueryEscape(state), nil)
		r.AddCookie(cookie)
		w := httptest.NewRecorder()
		h.OIDCCallback(w, r)
		return w
	}
	cookie, state := start(false, "")
	w := callback(cookie, state)
	if w.Code != 302 {
		t.Fatalf("browser: %d %s", w.Code, w.Body.String())
	}
	found := false
	for _, c := range w.Result().Cookies() {
		if c.Name == "217_session" && c.Value != "" {
			found = true
		}
	}
	if !found {
		t.Fatal("no session cookie")
	}
	existing, err := s.CreateUser("existing@example.com", "Existing", "password")
	if err != nil {
		t.Fatal(err)
	}
	subject, email = "existing-subject", "existing@example.com"
	cookie, state = start(false, "")
	if w = callback(cookie, state); w.Code != 302 || w.Header().Get("Location") != "https://app.example.com/app/?auth_error=account_exists" {
		t.Fatalf("unverified existing email: %d %s", w.Code, w.Header().Get("Location"))
	}
	verified = true
	if err := s.SetPasswordCredential(existing.ID, "hash"); err != nil {
		t.Fatal(err)
	}
	for _, native := range []bool{false, true} {
		cookie, state = start(native, pkceChallengeS256(strings.Repeat("a", 43)))
		w = callback(cookie, state)
		want := "https://app.example.com/app/?auth_error=account_exists"
		if native {
			want = oidcAppURL + "?error=account_exists"
		}
		if w.Code != 302 || w.Header().Get("Location") != want {
			t.Fatalf("password account: %d %s", w.Code, w.Header().Get("Location"))
		}
		cookie, state = start(native, pkceChallengeS256(strings.Repeat("a", 43)))
		r := httptest.NewRequest("GET", "https://app.example.com/api/auth/oidc/callback?error=access_denied&state="+url.QueryEscape(state), nil)
		r.AddCookie(cookie)
		w = httptest.NewRecorder()
		h.OIDCCallback(w, r)
		want = "https://app.example.com/app/?auth_error=oidc_failed"
		if native {
			want = oidcAppURL + "?error=oidc_failed"
		}
		if w.Code != 302 || w.Header().Get("Location") != want {
			t.Fatalf("cancel: %d %s", w.Code, w.Header().Get("Location"))
		}
		cookie, state = start(native, pkceChallengeS256(strings.Repeat("a", 43)))
		failExchange = true
		w = callback(cookie, state)
		failExchange = false
		if w.Code != 302 || w.Header().Get("Location") != want {
			t.Fatalf("exchange failure: %d %s", w.Code, w.Header().Get("Location"))
		}
	}
	if err := s.DeletePasswordCredential(existing.ID); err != nil {
		t.Fatal(err)
	}
	cookie, state = start(false, "")
	if w = callback(cookie, state); w.Code != 302 {
		t.Fatalf("verified existing email: %d", w.Code)
	}
	ids, err := s.OIDCIdentities(existing.ID)
	if err != nil || len(ids) != 1 {
		t.Fatalf("identity not linked: %v", err)
	}
	subject, email, verified = "subject", "oidc@example.com", false
	verifier := strings.Repeat("a", 43)
	cookie, state = start(true, pkceChallengeS256(verifier))
	w = callback(cookie, state)
	u, err := url.Parse(w.Header().Get("Location"))
	if err != nil || u.Scheme != "com.caldasstudios.app217" {
		t.Fatalf("native: %d %s", w.Code, w.Body.String())
	}
	code := u.Query().Get("code")
	exchange := func(v string) int {
		r := httptest.NewRequest("POST", "/api/auth/oidc/exchange", strings.NewReader(fmt.Sprintf(`{"code":%q,"code_verifier":%q}`, code, v)))
		w := httptest.NewRecorder()
		h.ExchangeOIDC(w, r)
		return w.Code
	}
	if status := exchange("wrong"); status != 400 {
		t.Fatalf("wrong verifier: %d", status)
	}
	if status := exchange(verifier); status != 400 {
		t.Fatalf("code not burned: %d", status)
	}
	cookie, state = start(true, pkceChallengeS256(verifier))
	w = callback(cookie, state)
	u, _ = url.Parse(w.Header().Get("Location"))
	code = u.Query().Get("code")
	if status := exchange(verifier); status != 200 {
		t.Fatalf("exchange: %d", status)
	}
	if status := exchange(verifier); status != 400 {
		t.Fatalf("replay: %d", status)
	}
	// A native code must never be usable as a link-start token.
	cookie, state = start(true, pkceChallengeS256(verifier))
	w = callback(cookie, state)
	u, _ = url.Parse(w.Header().Get("Location"))
	r := httptest.NewRequest("GET", "https://app.example.com/api/auth/oidc/link?token="+url.QueryEscape(u.Query().Get("code")), nil)
	w = httptest.NewRecorder()
	h.StartOIDCLink(w, r)
	if w.Code != 400 {
		t.Fatalf("native code accepted as link token: %d", w.Code)
	}
	owner, err := s.CreateUser("link@example.com", "Link", "password")
	if err != nil {
		t.Fatal(err)
	}
	if err := s.CreateSession(owner.ID, "oidc-test-session", time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	session := &http.Cookie{Name: "217_session", Value: "oidc-test-session"}
	authedRequest := func(method, path string, cookie *http.Cookie, body []byte) *http.Request {
		r := httptest.NewRequest(method, path, strings.NewReader(string(body)))
		r.AddCookie(cookie)
		return r
	}
	link := func(subjectValue string) *httptest.ResponseRecorder {
		t.Helper()
		subject = subjectValue
		r := authedRequest("POST", "https://app.example.com/api/account/oidc/link", session, []byte(`{"platform":"android"}`))
		r.Header.Set("Origin", "https://app.example.com")
		w := httptest.NewRecorder()
		h.AuthMiddleware(h.BeginOIDCLink)(w, r)
		var body map[string]string
		json.Unmarshal(w.Body.Bytes(), &body)
		if w.Code != 200 {
			t.Fatalf("link start: %d %s", w.Code, w.Body.String())
		}
		r = httptest.NewRequest("GET", body["url"], nil)
		w = httptest.NewRecorder()
		h.StartOIDCLink(w, r)
		provider, err := url.Parse(w.Header().Get("Location"))
		if err != nil || w.Code != 302 {
			t.Fatalf("link redirect: %d", w.Code)
		}
		if provider.Query().Get("prompt") != "login" {
			t.Fatal("link did not force provider login")
		}
		nonce, challenge = provider.Query().Get("nonce"), provider.Query().Get("code_challenge")
		return callback(w.Result().Cookies()[0], provider.Query().Get("state"))
	}
	other, err := s.CreateUser("other@example.com", "Other", "password")
	if err != nil {
		t.Fatal(err)
	}
	if err := s.CreateSession(other.ID, "other-session", time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	otherSession := &http.Cookie{Name: "217_session", Value: "other-session"}
	confirm := func(subject string, cookie *http.Cookie) int {
		t.Helper()
		w := link(subject)
		u, err := url.Parse(w.Header().Get("Location"))
		if err != nil || u.Query().Get("link_code") == "" {
			t.Fatalf("link callback: %d %s", w.Code, w.Header().Get("Location"))
		}
		r := authedRequest("POST", "/api/account/oidc/link/confirm", cookie, []byte(fmt.Sprintf(`{"code":%q}`, u.Query().Get("link_code"))))
		r.Header.Set("Origin", "https://app.example.com")
		w = httptest.NewRecorder()
		h.AuthMiddleware(h.ConfirmOIDCLink)(w, r)
		status := w.Code
		r = authedRequest("POST", "/api/account/oidc/link/confirm", cookie, []byte(fmt.Sprintf(`{"code":%q}`, u.Query().Get("link_code"))))
		r.Header.Set("Origin", "https://app.example.com")
		w = httptest.NewRecorder()
		h.AuthMiddleware(h.ConfirmOIDCLink)(w, r)
		if w.Code != 400 {
			t.Fatalf("confirmation code replay: %d", w.Code)
		}
		return status
	}
	if status := confirm("subject", session); status != 409 {
		t.Fatalf("identity already linked: %d", status)
	}
	if status := confirm("new-link", otherSession); status != 403 {
		t.Fatalf("different user: %d", status)
	}
	ids, err = s.OIDCIdentities(owner.ID)
	if err != nil || len(ids) != 0 {
		t.Fatal("identity attached without owner confirmation")
	}
	if status := confirm("new-link", session); status != 204 {
		t.Fatalf("owner confirmation: %d", status)
	}
	ids, err = s.OIDCIdentities(owner.ID)
	if err != nil || len(ids) != 1 || ids[0].Subject != "new-link" {
		t.Fatal("identity attached to wrong user")
	}
	h.SetWorkOSDisabled(true)
	r = authedRequest("DELETE", "https://app.example.com/api/account/oidc", session, nil)
	r.Header.Set("Origin", "https://app.example.com")
	w = httptest.NewRecorder()
	h.AuthMiddleware(h.DeleteOIDC)(w, r)
	if w.Code != 409 {
		t.Fatalf("unlink only method: %d", w.Code)
	}
	if err := s.SetPasswordCredential(owner.ID, "hash"); err != nil {
		t.Fatal(err)
	}
	r = authedRequest("DELETE", "https://app.example.com/api/account/oidc", session, nil)
	r.Header.Set("Origin", "https://app.example.com")
	w = httptest.NewRecorder()
	h.AuthMiddleware(h.DeleteOIDC)(w, r)
	if w.Code != 204 {
		t.Fatalf("unlink with password: %d", w.Code)
	}
}
