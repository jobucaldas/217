package server

import (
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
