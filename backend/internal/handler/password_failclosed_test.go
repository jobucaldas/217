package handler_test

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"217/backend/internal/handler"
	"217/backend/internal/model"
	"217/backend/internal/store"
)

// errStore fails every password-related call, to prove the handlers fail
// closed instead of issuing sessions or half-made accounts.
type errStore struct {
	*store.MemoryStore
	failHasVerification    bool
	failCreatePassword     bool
	failCreateVerification bool
}

func (s *errStore) HasEmailVerification(userID string) (bool, error) {
	if s.failHasVerification {
		return false, errors.New("store down")
	}
	return s.MemoryStore.HasEmailVerification(userID)
}

func (s *errStore) SetPasswordCredential(userID string, hash string) error {
	if s.failCreatePassword {
		return errors.New("store down")
	}
	return s.MemoryStore.SetPasswordCredential(userID, hash)
}

func (s *errStore) CreateEmailVerification(userID, code string, expiresAt time.Time) error {
	if s.failCreateVerification {
		return errors.New("store down")
	}
	return s.MemoryStore.CreateEmailVerification(userID, code, expiresAt)
}

func (s *errStore) CreatePasswordUser(email, passwordHash, verificationCode string, verificationExpires time.Time) (*model.User, error) {
	// The store creates user + credential + verification atomically; fail
	// the whole thing when the verification row cannot be written.
	if s.failCreateVerification && verificationCode != "" {
		return nil, errors.New("store down")
	}
	return s.MemoryStore.CreatePasswordUser(email, passwordHash, verificationCode, verificationExpires)
}

func TestPasswordLoginFailsClosedOnStoreError(t *testing.T) {
	h := handler.New(&errStore{MemoryStore: store.NewMemoryStore()})
	h.SetMailer(&fakeMailer{})
	// A verified account with a working credential.
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"closed@example.com","password":"long-enough-password"}`))
	w := httptest.NewRecorder()
	h.SignupPassword(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("signup status %d", w.Code)
	}
}

func TestPasswordSignupFailsClosedWhenVerificationRowFails(t *testing.T) {
	s := &errStore{MemoryStore: store.NewMemoryStore()}
	s.failCreateVerification = true
	h := handler.New(s)
	h.SetMailer(&fakeMailer{}) // mail on: the verification row is required
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"rollback@example.com","password":"long-enough-password"}`))
	w := httptest.NewRecorder()
	h.SignupPassword(w, req)
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("signup with failing verification store must 500, got %d", w.Code)
	}
	// The store failed inside CreatePasswordUser, so nothing was created:
	// the email is free (no half-made account lingers).
	if _, err := s.GetUserByEmail("rollback@example.com"); err == nil {
		t.Fatal("failed signup must not leave a user behind")
	}
	if s.failCreateVerification = false; true {
		req = httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
			strings.NewReader(`{"email":"rollback@example.com","password":"long-enough-password"}`))
		w = httptest.NewRecorder()
		h.SignupPassword(w, req)
		if w.Code != http.StatusCreated {
			t.Fatalf("email must be free after failed signup, got %d", w.Code)
		}
	}
}
