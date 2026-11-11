package handler_test

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestPasswordSignupAndLogin(t *testing.T) {
	h, _ := newTestHandler(t)
	// Sign up.
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"New@Example.com","password":"long-enough-password"}`))
	w := httptest.NewRecorder()
	h.SignupPassword(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("signup status %d: %s", w.Code, w.Body.String())
	}
	// Login works (no mail configured, so no verification).
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"new@example.com","password":"long-enough-password"}`))
	w = httptest.NewRecorder()
	h.LoginPassword(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("login status %d: %s", w.Code, w.Body.String())
	}
	// Unknown email and wrong password are indistinguishable (401, same body).
	for _, body := range []string{
		`{"email":"nobody@example.com","password":"long-enough-password"}`,
		`{"email":"new@example.com","password":"wrong-password-entirely"}`,
	} {
		req = httptest.NewRequest(http.MethodPost, "/api/auth/password/login", strings.NewReader(body))
		w = httptest.NewRecorder()
		h.LoginPassword(w, req)
		if w.Code != http.StatusUnauthorized || strings.Contains(w.Body.String(), "nobody") {
			t.Fatalf("expected plain 401, got %d: %s", w.Code, w.Body.String())
		}
	}
}

func TestPasswordSignupRefusesExistingEmail(t *testing.T) {
	h, s := newTestHandler(t)
	if _, err := s.CreateUser("taken@example.com", "Taken", "password123"); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"taken@example.com","password":"long-enough-password"}`))
	w := httptest.NewRecorder()
	h.SignupPassword(w, req)
	if w.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d: %s", w.Code, w.Body.String())
	}
}

func TestPasswordSignupWeakPassword(t *testing.T) {
	h, _ := newTestHandler(t)
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"weak@example.com","password":"password123"}`))
	w := httptest.NewRecorder()
	h.SignupPassword(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

func TestPasswordSignupDisabled(t *testing.T) {
	h, _ := newTestHandler(t)
	h.SetPasswordEnabled(false)
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"x@example.com","password":"long-enough-password"}`))
	w := httptest.NewRecorder()
	h.SignupPassword(w, req)
	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", w.Code)
	}
}

func TestPasswordLoginLockout(t *testing.T) {
	h, _ := newTestHandler(t)
	// 15 failed attempts (distinct accounts, like a stuffing run) lock the
	// address out for every account.
	for i := 0; i < 15; i++ {
		email := fmt.Sprintf("user%d@example.com", i)
		req := httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
			strings.NewReader(`{"email":"`+email+`","password":"wrong-password-entirely"}`))
		req.RemoteAddr = "203.0.113.50:1234"
		w := httptest.NewRecorder()
		h.LoginPassword(w, req)
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("attempt %d: expected 401, got %d", i+1, w.Code)
		}
	}
	// The next attempt from the same address is refused even with a fresh
	// account; another address is unaffected.
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"someone@example.com","password":"wrong-password-entirely"}`))
	req.RemoteAddr = "203.0.113.50:1234"
	w := httptest.NewRecorder()
	h.LoginPassword(w, req)
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("locked address must be refused, got %d", w.Code)
	}
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"someone@example.com","password":"wrong-password-entirely"}`))
	req.RemoteAddr = "203.0.113.51:1234"
	w = httptest.NewRecorder()
	h.LoginPassword(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("other address must not be locked, got %d", w.Code)
	}
}

// TestPasswordLoginDelayTarpit covers the per-account tarpit: a correct
// password is never refused because of earlier failures, and concurrent
// guesses are serialized (each waits for the ones before it).
func TestPasswordLoginDelayTarpit(t *testing.T) {
	h, _ := newTestHandler(t)
	// Sign up so the account has a password credential.
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"tarpit@example.com","password":"long-enough-password"}`))
	w := httptest.NewRecorder()
	h.SignupPassword(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("signup status %d: %s", w.Code, w.Body.String())
	}
	// One failed attempt, then a correct one: it must go through.
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"tarpit@example.com","password":"wrong-password-entirely"}`))
	w = httptest.NewRecorder()
	h.LoginPassword(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("first wrong attempt: expected 401, got %d", w.Code)
	}
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"tarpit@example.com","password":"long-enough-password"}`))
	w = httptest.NewRecorder()
	h.LoginPassword(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("correct login after failures must pass, got %d: %s", w.Code, w.Body.String())
	}
}

func TestPasswordLoginDelaySerializes(t *testing.T) {
	h, _ := newTestHandler(t)
	h.SetDelayTimings(50*time.Millisecond, 200*time.Millisecond, 15*time.Minute, 4)
	// Prime one failure so attempts carry a wait.
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"prime@example.com","password":"x"}`))
	h.LoginPassword(httptest.NewRecorder(), req)
	// Six concurrent wrong attempts: the queue holds 4, the rest overflow.
	start := time.Now()
	var wg sync.WaitGroup
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
				strings.NewReader(`{"email":"prime@example.com","password":"x"}`))
			h.LoginPassword(httptest.NewRecorder(), r)
		}()
	}
	wg.Wait()
	elapsed := time.Since(start)
	// Each wrong attempt sleeps the full wait (50 ms), so the batch takes
	// at least a couple of waits even with the queue in play.
	if elapsed < 50*time.Millisecond {
		t.Fatalf("concurrent attempts must be serialized, took %s", elapsed)
	}
}

func TestChangePasswordRequiresCurrent(t *testing.T) {
	h, s := newTestHandler(t)
	user, err := s.CreateUser("change@example.com", "Change", "password123")
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)
	// Set the first password: no current required.
	req := authedRequest(http.MethodPut, "/api/account/password", cookie,
		[]byte(`{"new_password":"first-long-password"}`))
	w := httptest.NewRecorder()
	h.AuthMiddleware(h.ChangePassword)(w, req)
	if w.Code != http.StatusNoContent {
		t.Fatalf("set status %d: %s", w.Code, w.Body.String())
	}
	// Changing it without the current password is refused.
	req = authedRequest(http.MethodPut, "/api/account/password", cookie,
		[]byte(`{"new_password":"second-long-password"}`))
	w = httptest.NewRecorder()
	h.AuthMiddleware(h.ChangePassword)(w, req)
	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 without current password, got %d", w.Code)
	}
	// With it, the change goes through.
	req = authedRequest(http.MethodPut, "/api/account/password", cookie,
		[]byte(`{"current_password":"first-long-password","new_password":"second-long-password"}`))
	w = httptest.NewRecorder()
	h.AuthMiddleware(h.ChangePassword)(w, req)
	if w.Code != http.StatusNoContent {
		t.Fatalf("change status %d: %s", w.Code, w.Body.String())
	}
}
