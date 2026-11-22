package main

import (
	"bytes"
	"strings"
	"testing"
	"time"

	"217/backend/internal/passwordauth"
	"217/backend/internal/store"
)

func TestResetPasswordRevokesSessionsAndDevices(t *testing.T) {
	s := store.NewMemoryStore()
	u, err := s.CreateUser("reset@example.com", "", "")
	if err != nil {
		t.Fatal(err)
	}
	key, err := s.CreateDeviceKey(u.ID, []byte("test-key"))
	if err != nil {
		t.Fatal(err)
	}
	if err := s.CreateDeviceSession(u.ID, key, "device-session", time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := s.CreateSession(u.ID, "session", time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if err := resetPassword(s, "missing@example.com", strings.NewReader("A secure password example 123\n"), &out); err == nil {
		t.Fatal("missing account accepted")
	}
	if err := resetPassword(s, u.Email, strings.NewReader("password12345678\n"), &out); err == nil {
		t.Fatal("blocklisted password accepted")
	}
	if err := resetPassword(s, u.Email, strings.NewReader("A secure password example 123\n"), &out); err != nil {
		t.Fatal(err)
	}
	hash, err := s.GetPasswordCredential(u.ID)
	if err != nil || !passwordauth.Verify("A secure password example 123", hash) {
		t.Fatal("password not replaced")
	}
	for _, token := range []string{"session", "device-session"} {
		if _, err := s.GetUserBySession(token); err == nil {
			t.Fatal("session was not revoked")
		}
	}
	if err := s.SetDeviceChallenge(key, "challenge", time.Now().Add(time.Minute)); err == nil {
		t.Fatal("device was not revoked")
	}
	if strings.Contains(out.String(), "A secure password") {
		t.Fatal("password printed")
	}
}
