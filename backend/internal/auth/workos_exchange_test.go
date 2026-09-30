package auth

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestWorkOSExchangeAgainstMockAuthKit(t *testing.T) {
	var sawCode, sawVerifier, sawAuth, sawSecret string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/user_management/authenticate" {
			http.NotFound(w, r)
			return
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		sawCode, _ = body["code"].(string)
		sawVerifier, _ = body["code_verifier"].(string)
		sawSecret, _ = body["client_secret"].(string)
		sawAuth = r.Header.Get("Authorization")
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"user": map[string]any{
				"id":             "user_01TEST",
				"email":          "native@example.com",
				"email_verified": true,
				"first_name":     "Native",
				"last_name":      "User",
			},
			"access_token":  "access",
			"refresh_token": "refresh",
		})
	}))
	defer server.Close()

	provider, err := NewWorkOSOAuth("sk_test_secret", "client_test", "http://localhost:8080")
	if err != nil {
		t.Fatal(err)
	}
	provider.apiBaseURL = server.URL
	provider.httpClient = server.Client()
	info, err := provider.ExchangeWithRedirect(context.Background(), "auth-code", "pkce-verifier", "com.jobucaldas.a217://auth/callback")
	if err != nil {
		t.Fatalf("exchange: %v", err)
	}
	if sawCode != "auth-code" || sawVerifier != "pkce-verifier" {
		t.Fatalf("unexpected authenticate payload code=%q verifier=%q", sawCode, sawVerifier)
	}
	if sawAuth != "" || sawSecret != "" {
		t.Fatalf("PKCE exchange must not send API key material auth=%q secret=%q", sawAuth, sawSecret)
	}
	if info.Subject != "user_01TEST" || info.Email != "native@example.com" || !info.EmailVerified || info.Name != "Native User" {
		t.Fatalf("unexpected user info: %#v", info)
	}
	if !info.AuthoritativeEmail() {
		t.Fatal("verified WorkOS email should be authoritative")
	}
	if _, err := provider.ExchangeWithRedirect(context.Background(), "auth-code", "pkce-verifier", "https://evil.example/callback"); err == nil {
		t.Fatal("expected unregistered redirect to be rejected")
	}
}
