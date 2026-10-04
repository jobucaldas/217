package server

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	webpush "github.com/SherClockHolmes/webpush-go"
)

func TestValidatePushConfigAllowsDisabled(t *testing.T) {
	cfg, err := ValidatePushConfig(PushConfig{})
	if err != nil {
		t.Fatalf("expected disabled push config to be valid, got %v", err)
	}
	if cfg.PublicKey != "" || cfg.PrivateKey != "" || cfg.Subject != "" {
		t.Fatalf("expected disabled config to round-trip empty, got %#v", cfg)
	}
}

func TestValidatePushConfigAcceptsGeneratedKeyPair(t *testing.T) {
	privateKey, publicKey, err := webpush.GenerateVAPIDKeys()
	if err != nil {
		t.Fatalf("failed to generate VAPID keys: %v", err)
	}

	cfg, err := ValidatePushConfig(PushConfig{
		PublicKey:  publicKey,
		PrivateKey: privateKey,
		Subject:    "mailto:test@example.com",
	})
	if err != nil {
		t.Fatalf("expected generated VAPID keys to validate, got %v", err)
	}
	if cfg.PublicKey != publicKey || cfg.PrivateKey != privateKey || cfg.Subject != "mailto:test@example.com" {
		t.Fatalf("unexpected validated config: %#v", cfg)
	}
}

func TestValidatePushConfigRejectsIncompleteOrInvalidInputs(t *testing.T) {
	if _, err := ValidatePushConfig(PushConfig{PublicKey: "abc"}); err == nil {
		t.Fatal("expected incomplete push config to fail")
	}
	if _, err := ValidatePushConfig(PushConfig{PublicKey: "abc", PrivateKey: "def", Subject: "not-a-url"}); err == nil {
		t.Fatal("expected malformed push config to fail")
	}
}

func TestOriginFromValidatedBaseURL(t *testing.T) {
	for _, baseURL := range []string{"http://localhost:8080", "https://app.example"} {
		if got := originFromBaseURL(baseURL); got != baseURL {
			t.Fatalf("originFromBaseURL(%q) = %q", baseURL, got)
		}
	}
}

func TestHardeningMiddleware(t *testing.T) {
	var readErr error
	h := secureHeaders(limitBody(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, readErr = io.ReadAll(r.Body)
	})))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/entries/2026-10-01", strings.NewReader(`{"notes":"x"}`)))
	if readErr != nil {
		t.Fatalf("small body rejected: %v", readErr)
	}
	for header, want := range map[string]string{"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY"} {
		if got := rec.Header().Get(header); got != want {
			t.Errorf("%s = %q, want %q", header, got, want)
		}
	}

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/api/entries/2026-10-01", strings.NewReader(strings.Repeat("x", maxBodyBytes+1))))
	if readErr == nil {
		t.Fatal("oversized body accepted")
	}
}

func TestDatabaseTLSVerified(t *testing.T) {
	for dsn, want := range map[string]bool{
		"postgres://u:p@postgres:5432/217?sslmode=verify-full&sslrootcert=/certs/ca.crt": true,
		"postgres://u:p@postgres:5432/217?sslmode=require":                               false,
		"postgres://u:p@postgres:5432/217?sslmode=disable":                               false,
		"postgres://u:p@postgres:5432/217":                                               false,
	} {
		if got := databaseTLSVerified(dsn); got != want {
			t.Errorf("databaseTLSVerified(%q) = %v", dsn, got)
		}
	}
}
