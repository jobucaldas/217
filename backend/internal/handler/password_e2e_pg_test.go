package handler_test

import (
	"crypto/rand"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"217/backend/internal/fieldcrypt"
	"217/backend/internal/handler"
	"217/backend/internal/store"
)

// keyringForTest builds a throwaway AES keyring for the PG store.
func keyringForTest(t *testing.T) *fieldcrypt.Keyring {
	t.Helper()
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	kr, err := fieldcrypt.New(key)
	if err != nil {
		t.Fatal(err)
	}
	return kr
}

// TestSignupLoginEndToEndPG runs signup then login through the handler
// against the PostgreSQL store, covering the sealed-column split and the
// password_credentials row on the real database. Skips when the DSN is unset.
func TestSignupLoginEndToEndPG(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set TEST_DATABASE_URL to a disposable PostgreSQL database")
	}
	s, err := store.NewPGStore(dsn, keyringForTest(t))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	// The store tests migrate a throwaway schema; the handler test needs
	// the same tables, so run the migrations for this store too.
	kr := keyringForTest(t) // same keyring must seal and open the rows
	if err := store.MigrateForTest(s, kr); err != nil {
		t.Fatal(err)
	}
	h := handler.New(s)

	// Signup.
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"e2e@example.com","password":"long-enough-password"}`))
	w := httptest.NewRecorder()
	h.SignupPassword(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("signup status %d: %s", w.Code, w.Body.String())
	}

	// Login with the same password must succeed.
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"e2e@example.com","password":"long-enough-password"}`))
	w = httptest.NewRecorder()
	h.LoginPassword(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("login after signup: expected 200, got %d: %s", w.Code, w.Body.String())
	}

	// The credential round-trips through password_credentials.
	id, hash, err := s.LookupPasswordHashByEmail("e2e@example.com")
	if err != nil || id == "" {
		t.Fatalf("credential must exist after signup: %q %v", id, err)
	}
	if hash == "" {
		t.Fatal("password credential must be stored after signup")
	}
}
