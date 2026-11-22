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

func TestOIDCBrowserAndNative(t *testing.T) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	var issuer, nonce, challenge string
	var verified bool
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
	if w = callback(cookie, state); w.Code != 403 {
		t.Fatalf("unverified existing email: %d", w.Code)
	}
	verified = true
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
		nonce, challenge = provider.Query().Get("nonce"), provider.Query().Get("code_challenge")
		return callback(w.Result().Cookies()[0], provider.Query().Get("state"))
	}
	if w = link("subject"); !strings.Contains(w.Header().Get("Location"), "link_error") {
		t.Fatal("linked identity owned by another user")
	}
	if w = link("new-link"); !strings.Contains(w.Header().Get("Location"), "linked=1") {
		t.Fatalf("link failed: %d %s", w.Code, w.Body.String())
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
