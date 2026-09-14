package auth

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"math/big"
	"sync/atomic"
	"time"

	"encoding/json"
	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/golang-jwt/jwt/v5"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
)

func TestGoogleOAuthExactCallbackAndPKCE(t *testing.T) {
	g, err := NewGoogleOAuth("client", "secret", "https://app.example/")
	if err != nil {
		t.Fatal(err)
	}
	if g.config.RedirectURL != "https://app.example/api/auth/google/callback" {
		t.Fatalf("unexpected callback %q", g.config.RedirectURL)
	}
	parsed, err := url.Parse(g.AuthCodeURL("state", "challenge", "nonce"))
	if err != nil {
		t.Fatal(err)
	}
	if parsed.Query().Get("nonce") != "nonce" || parsed.Query().Get("scope") != "openid email profile" || parsed.Query().Get("access_type") != "" {
		t.Fatalf("unexpected nonce/scopes/access type: %s", parsed.RawQuery)
	}
	if parsed.Query().Get("code_challenge") != "challenge" || parsed.Query().Get("code_challenge_method") != "S256" {
		t.Fatalf("missing PKCE parameters: %s", parsed.RawQuery)
	}
}

func TestValidateAppBaseURL(t *testing.T) {
	valid := map[string]string{
		"http://localhost:8080/": "http://localhost:8080",
		"http://127.0.0.1:8080":  "http://127.0.0.1:8080",
		"http://[::1]:8080":      "http://[::1]:8080",
		"https://app.example/":   "https://app.example",
	}
	for input, expected := range valid {
		got, err := ValidateAppBaseURL(input)
		if err != nil || got != expected {
			t.Errorf("ValidateAppBaseURL(%q) = %q, %v; want %q", input, got, err, expected)
		}
	}
	invalid := []string{
		"http://app.example", "https://user:pass@app.example", "https://app.example/path",
		"https://app.example?query=1", "https://app.example#fragment", "ftp://app.example",
	}
	for _, input := range invalid {
		if _, err := ValidateAppBaseURL(input); err == nil {
			t.Errorf("ValidateAppBaseURL(%q) unexpectedly succeeded", input)
		}
	}
}

func signedGoogleToken(t *testing.T, key *rsa.PrivateKey, kid string, claims jwt.MapClaims) string {
	t.Helper()
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	token.Header["kid"] = kid
	raw, err := token.SignedString(key)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func googleClaims() jwt.MapClaims {
	return jwt.MapClaims{"iss": "https://accounts.google.com", "aud": "client", "sub": "subject", "exp": time.Now().Add(time.Hour).Unix(), "nonce": "nonce", "email": "user@example.com", "email_verified": true, "hd": "example.com", "name": "User"}
}

func jwk(key *rsa.PrivateKey, kid string) map[string]any {
	return map[string]any{"kty": "RSA", "alg": "RS256", "use": "sig", "kid": kid,
		"n": base64.RawURLEncoding.EncodeToString(key.N.Bytes()),
		"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes())}
}

func TestGoogleIDTokenValidation(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	wrongKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name  string
		claim string
		value any
		valid bool
	}{
		{"valid", "", nil, true},
		{"google issuer without scheme", "iss", "accounts.google.com", true},
		{"wrong issuer", "iss", "https://attacker.example", false},
		{"wrong audience", "aud", "another-client", false},
		{"expired", "exp", time.Now().Add(-time.Minute).Unix(), false},
		{"missing expiry", "exp", nil, false},
		{"empty subject", "sub", "", false},
		{"wrong nonce", "nonce", "another-attempt", false},
		{"missing nonce", "nonce", nil, false},
		{"wrong authorized party", "azp", "another-client", false},
		{"multiple audiences without azp", "aud", []string{"client", "another-client"}, false},
		{"bad signature", "", nil, false},
		{"missing token", "", nil, false},
		{"malformed token", "", nil, false},
		{"empty expected nonce", "", nil, false},
		{"unavailable JWKS", "", nil, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			claims := googleClaims()
			if test.claim != "" {
				if test.value == nil {
					delete(claims, test.claim)
				} else {
					claims[test.claim] = test.value
				}
			}
			signingKey := key
			if test.name == "bad signature" {
				signingKey = wrongKey
			}
			raw := signedGoogleToken(t, signingKey, "key-1", claims)
			if test.name == "missing token" {
				raw = ""
			}
			if test.name == "malformed token" {
				raw = "not-a-jwt"
			}
			var verifier atomic.Value
			var unexpected atomic.Bool
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				switch r.URL.Path {
				case "/token":
					_ = r.ParseForm()
					verifier.Store(r.Form.Get("code_verifier"))
					_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "token", "token_type": "Bearer", "id_token": raw})
				case "/keys":
					if test.name == "unavailable JWKS" {
						w.WriteHeader(http.StatusServiceUnavailable)
						return
					}
					_ = json.NewEncoder(w).Encode(map[string]any{"keys": []any{jwk(key, "key-1")}})
				default:
					unexpected.Store(true)
					http.NotFound(w, r)
				}
			}))
			defer server.Close()
			g, err := NewGoogleOAuth("client", "secret", "http://localhost:8080")
			if err != nil {
				t.Fatal(err)
			}
			g.config.Endpoint.TokenURL = server.URL + "/token"
			g.verifier = oidc.NewVerifier("https://accounts.google.com", oidc.NewRemoteKeySet(oidc.ClientContext(context.Background(), g.httpClient), server.URL+"/keys"), &oidc.Config{ClientID: "client"})
			nonce := "nonce"
			if test.name == "empty expected nonce" {
				nonce = ""
			}
			info, err := g.Exchange(context.Background(), "code", "verifier", nonce)
			if (err == nil) != test.valid {
				t.Fatalf("valid=%v info=%#v err=%v", test.valid, info, err)
			}
			if test.valid && (verifier.Load() != "verifier" || info.Subject != "subject" || !info.AuthoritativeEmail()) {
				t.Fatalf("unexpected exchange: %#v", info)
			}
			if unexpected.Load() {
				t.Fatal("unexpected userinfo fallback")
			}
		})
	}
}

func TestGoogleJWKSRotation(t *testing.T) {
	keys := make([]*rsa.PrivateKey, 2)
	for i := range keys {
		var err error
		keys[i], err = rsa.GenerateKey(rand.Reader, 2048)
		if err != nil {
			t.Fatal(err)
		}
	}
	var active atomic.Int32
	var fetches atomic.Int32
	tokens := []string{signedGoogleToken(t, keys[0], "first", googleClaims()), signedGoogleToken(t, keys[1], "second", googleClaims())}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		i := active.Load()
		if r.URL.Path == "/token" {
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "token", "token_type": "Bearer", "id_token": tokens[i]})
			return
		}
		fetches.Add(1)
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []any{jwk(keys[i], []string{"first", "second"}[i])}})
	}))
	defer server.Close()
	g, err := NewGoogleOAuth("client", "secret", "http://localhost:8080")
	if err != nil {
		t.Fatal(err)
	}
	g.config.Endpoint.TokenURL = server.URL + "/token"
	g.verifier = oidc.NewVerifier("https://accounts.google.com", oidc.NewRemoteKeySet(oidc.ClientContext(context.Background(), g.httpClient), server.URL+"/keys"), &oidc.Config{ClientID: "client"})
	for i := range keys {
		active.Store(int32(i))
		if _, err := g.Exchange(context.Background(), "code", "verifier", "nonce"); err != nil {
			t.Fatal(err)
		}
	}
	if fetches.Load() < 2 {
		t.Fatal("rotated signing key did not refresh JWKS")
	}
}

func TestGoogleEmailAuthority(t *testing.T) {
	for _, test := range []struct {
		email, hd      string
		verified, want bool
	}{
		{"user@gmail.com", "", true, true},
		{"user@GMAIL.COM", "", true, true},
		{"user@example.com", "example.com", true, true},
		{"user@example.com", "", true, false},
		{"user@gmail.com.attacker.example", "", true, false},
		{"user@gmail.com", "", false, false},
		{"user@example.com", "example.com", false, false},
	} {
		info := OAuthUserInfo{Email: test.email, HostedDomain: test.hd, EmailVerified: test.verified}
		if info.AuthoritativeEmail() != test.want {
			t.Errorf("unexpected authority for %#v", test)
		}
	}
}
