package handler_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// fakeMailer captures verification codes handed to it.
type fakeMailer struct {
	codes []string
}

func (f *fakeMailer) SendVerification(to, code string) error {
	f.codes = append(f.codes, code)
	return nil
}

func TestPasswordVerifyEmailFlow(t *testing.T) {
	h, _ := newTestHandler(t)
	mail := &fakeMailer{}
	h.SetMailer(mail)

	// Sign up: the code is sent by mail.
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"verify@example.com","password":"long-enough-password"}`))
	w := httptest.NewRecorder()
	h.SignupPassword(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("signup status %d: %s", w.Code, w.Body.String())
	}
	if len(mail.codes) != 1 {
		t.Fatalf("expected one verification code, got %d", len(mail.codes))
	}
	code := mail.codes[0]

	// Login before verifying is refused, but the account is not consumed.
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"verify@example.com","password":"long-enough-password"}`))
	w = httptest.NewRecorder()
	h.LoginPassword(w, req)
	if w.Code != http.StatusForbidden {
		t.Fatalf("unverified login: expected 403, got %d", w.Code)
	}

	// A wrong code is refused and does not verify.
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/verify",
		strings.NewReader(`{"email":"verify@example.com","code":"000000"}`))
	w = httptest.NewRecorder()
	h.VerifyEmail(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("wrong code: expected 400, got %d", w.Code)
	}

	// The right code verifies.
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/verify",
		strings.NewReader(`{"email":"verify@example.com","code":"`+code+`"}`))
	w = httptest.NewRecorder()
	h.VerifyEmail(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("correct code: expected 200, got %d", w.Code)
	}

	// A code is single-use: the second verify fails.
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/verify",
		strings.NewReader(`{"email":"verify@example.com","code":"`+code+`"}`))
	w = httptest.NewRecorder()
	h.VerifyEmail(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("reused code must fail, got %d", w.Code)
	}

	// Now login works.
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"verify@example.com","password":"long-enough-password"}`))
	w = httptest.NewRecorder()
	h.LoginPassword(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("login after verify: expected 200, got %d", w.Code)
	}
}

func TestPasswordVerifyUnknownEmail(t *testing.T) {
	h, _ := newTestHandler(t)
	mail := &fakeMailer{}
	h.SetMailer(mail)
	// A known account exists so the responses can differ if the code leaks it.
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"known@example.com","password":"long-enough-password"}`))
	h.SignupPassword(httptest.NewRecorder(), req)

	// Wrong code on the known address and a verify for an unknown address:
	// both answer the same way.
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/verify",
		strings.NewReader(`{"email":"known@example.com","code":"000000"}`))
	w := httptest.NewRecorder()
	h.VerifyEmail(w, req)
	known := w.Code
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/verify",
		strings.NewReader(`{"email":"nobody@example.com","code":"000000"}`))
	w = httptest.NewRecorder()
	h.VerifyEmail(w, req)
	if w.Code != known {
		t.Fatalf("unknown email must look like a wrong code, got %d vs %d", w.Code, known)
	}
}

func TestPasswordVerifyExpiredCode(t *testing.T) {
	h, s := newTestHandler(t)
	mail := &fakeMailer{}
	h.SetMailer(mail)
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"expired@example.com","password":"long-enough-password"}`))
	h.SignupPassword(httptest.NewRecorder(), req)
	user, err := s.GetUserByEmail("expired@example.com")
	if err != nil || user == nil {
		t.Fatal("signed-up user not found")
	}
	// Replace the pending verification with one that expired already.
	if err := s.CreateEmailVerification(user.ID, "111111", time.Now().UTC().Add(-time.Minute)); err != nil {
		t.Fatal(err)
	}
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/verify",
		strings.NewReader(`{"email":"expired@example.com","code":"111111"}`))
	w := httptest.NewRecorder()
	h.VerifyEmail(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expired code must fail, got %d", w.Code)
	}
	// Login stays gated after an expired code.
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"expired@example.com","password":"long-enough-password"}`))
	w = httptest.NewRecorder()
	h.LoginPassword(w, req)
	if w.Code != http.StatusForbidden {
		t.Fatalf("expired code must not verify, login got %d", w.Code)
	}
}

func TestPasswordResendRateLimited(t *testing.T) {
	h, _ := newTestHandler(t)
	mail := &fakeMailer{}
	h.SetMailer(mail)
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"ratelimit@example.com","password":"long-enough-password"}`))
	h.SignupPassword(httptest.NewRecorder(), req)

	// The first resend goes through; hammering past the limit is refused.
	sent := 0
	for i := 0; i < 10; i++ {
		req := httptest.NewRequest(http.MethodPost, "/api/auth/password/verify/resend",
			strings.NewReader(`{"email":"ratelimit@example.com"}`))
		w := httptest.NewRecorder()
		h.ResendVerificationEmail(w, req)
		if w.Code == http.StatusOK {
			sent++
		}
	}
	if sent >= 10 {
		t.Fatalf("resend must be rate limited, all %d passed", sent)
	}
}

func TestPasswordNoMailerStillWorks(t *testing.T) {
	// Without a mailer, signup needs no verification at all.
	h, _ := newTestHandler(t)
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"nomail@example.com","password":"long-enough-password"}`))
	w := httptest.NewRecorder()
	h.SignupPassword(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("signup status %d", w.Code)
	}
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"nomail@example.com","password":"long-enough-password"}`))
	w = httptest.NewRecorder()
	h.LoginPassword(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("login without mail verification must pass, got %d", w.Code)
	}
}

// TestPasswordRemoveCredential covers the only-method guard: with no other
// method the password cannot be dropped; with WorkOS linked it can.
func TestPasswordRemoveCredential(t *testing.T) {
	h, s := newTestHandler(t)
	// Sign up: password only, no WorkOS identity.
	req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
		strings.NewReader(`{"email":"remove@example.com","password":"long-enough-password"}`))
	w := httptest.NewRecorder()
	h.SignupPassword(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("signup status %d", w.Code)
	}
	userRec, err := s.GetUserByEmail("remove@example.com")
	if err != nil || userRec == nil {
		t.Fatal("signed-up user not found")
	}
	cookie := sessionCookie(t, s, userRec.ID)

	// It is the only method: refused with 409.
	req = authedRequest(http.MethodDelete, "/api/account/password", cookie, nil)
	w = httptest.NewRecorder()
	h.AuthMiddleware(h.RemovePasswordCredential)(w, req)
	if w.Code != http.StatusConflict {
		t.Fatalf("only method must be refused with 409, got %d", w.Code)
	}

	// Link a WorkOS identity so another method remains.
	if _, err := s.LinkWorkOSIdentity("subject-remove", "remove@example.com", "Remove", true); err != nil {
		t.Fatal(err)
	}
	req = authedRequest(http.MethodDelete, "/api/account/password", cookie, nil)
	w = httptest.NewRecorder()
	h.AuthMiddleware(h.RemovePasswordCredential)(w, req)
	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204 with another method, got %d: %s", w.Code, w.Body.String())
	}

	// The old password no longer signs in.
	req = httptest.NewRequest(http.MethodPost, "/api/auth/password/login",
		strings.NewReader(`{"email":"remove@example.com","password":"long-enough-password"}`))
	w = httptest.NewRecorder()
	h.LoginPassword(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("removed credential must not sign in, got %d", w.Code)
	}
}
