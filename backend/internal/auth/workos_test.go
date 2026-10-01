package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/workos/workos-go/v10"
)

func TestWorkOSOAuthExactCallbackAndPKCE(t *testing.T) {
	w, err := NewWorkOSOAuth("sk_test", "client_test", "https://app.example/")
	if err != nil {
		t.Fatal(err)
	}
	if w.RedirectURI() != "https://app.example/api/auth/workos/callback" {
		t.Fatalf("unexpected callback %q", w.RedirectURI())
	}
	parsed, err := url.Parse(w.AuthCodeURL("state", "challenge", "nonce"))
	if err != nil {
		t.Fatal(err)
	}
	q := parsed.Query()
	if q.Get("client_id") != "client_test" || q.Get("redirect_uri") != "https://app.example/api/auth/workos/callback" {
		t.Fatalf("unexpected client/redirect: %s", parsed.RawQuery)
	}
	if q.Get("provider") != "authkit" || q.Get("response_type") != "code" {
		t.Fatalf("unexpected provider/response: %s", parsed.RawQuery)
	}
	if q.Get("state") != "state" || q.Get("code_challenge") != "challenge" || q.Get("code_challenge_method") != "S256" {
		t.Fatalf("missing PKCE/state parameters: %s", parsed.RawQuery)
	}
}

func TestWorkOSDeleteUserCallsUserManagementAPI(t *testing.T) {
	var gotMethod, gotPath, gotAuth string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotMethod = r.Method
		gotPath = r.URL.Path
		gotAuth = r.Header.Get("Authorization")
		w.WriteHeader(http.StatusNoContent)
	}))
	t.Cleanup(server.Close)

	client, err := NewWorkOSOAuth("sk_test_delete", "client_test", "https://app.example")
	if err != nil {
		t.Fatal(err)
	}
	client.client = workos.NewClient("sk_test_delete", workos.WithBaseURL(server.URL))

	if err := client.DeleteUser(context.Background(), "user_01DELETEME"); err != nil {
		t.Fatalf("DeleteUser: %v", err)
	}
	if gotMethod != http.MethodDelete || gotPath != "/user_management/users/user_01DELETEME" {
		t.Fatalf("unexpected request %s %s", gotMethod, gotPath)
	}
	if gotAuth != "Bearer sk_test_delete" {
		t.Fatalf("expected API key auth, got %q", gotAuth)
	}
}

func TestWorkOSDeleteUserTreatsNotFoundAsSuccess(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"code":"entity_not_found","message":"User not found"}`))
	}))
	t.Cleanup(server.Close)

	client, err := NewWorkOSOAuth("sk_test_delete", "client_test", "https://app.example")
	if err != nil {
		t.Fatal(err)
	}
	client.client = workos.NewClient("sk_test_delete", workos.WithBaseURL(server.URL))
	if err := client.DeleteUser(context.Background(), "user_already_gone"); err != nil {
		t.Fatalf("expected 404 to be OK, got %v", err)
	}
}

func TestWorkOSDeleteUserRequiresAPIKey(t *testing.T) {
	client, err := NewWorkOSOAuth("", "client_test", "https://app.example")
	if err != nil {
		t.Fatal(err)
	}
	if err := client.DeleteUser(context.Background(), "user_01"); err == nil {
		t.Fatal("expected error without API key")
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

func TestWorkOSEmailAuthority(t *testing.T) {
	for _, test := range []struct {
		verified, want bool
	}{
		{true, true},
		{false, false},
	} {
		info := OAuthUserInfo{Email: "user@example.com", EmailVerified: test.verified}
		if info.AuthoritativeEmail() != test.want {
			t.Errorf("unexpected authority for verified=%v", test.verified)
		}
	}
}

func TestUserInfoFromWorkOSRequiresClaims(t *testing.T) {
	if _, err := userInfoFromWorkOS(nil); err == nil {
		t.Fatal("expected error for nil response")
	}
}
