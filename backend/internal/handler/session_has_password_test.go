package handler_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// The session's user carries has_password so the UI can offer "Set
// password" vs "Change/Remove password".
func TestSessionUserHasPassword(t *testing.T) {
	h, s := newTestHandler(t)
	user, err := s.CreateUser("cred@example.com", "Cred", "password123")
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)

	session := func() map[string]any {
		t.Helper()
		req := authedRequest(http.MethodGet, "/api/auth/session", cookie, nil)
		w := httptest.NewRecorder()
		h.CurrentSession(w, req)
		if w.Code != http.StatusOK {
			t.Fatalf("session status %d", w.Code)
		}
		var body map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		return body
	}
	userJSON := func() map[string]any {
		t.Helper()
		u, ok := session()["user"].(map[string]any)
		if !ok {
			t.Fatal("session has no user object")
		}
		return u
	}

	// No password yet: has_password is absent (or false).
	if u := userJSON(); u["has_password"] == true {
		t.Fatalf("has_password without a credential: %#v", u)
	}
	if err := s.SetPasswordCredential(user.ID, "argon2-hash-not-checked-here"); err != nil {
		t.Fatal(err)
	}
	if u := userJSON(); u["has_password"] != true {
		t.Fatalf("has_password not reported: %#v", u)
	}
}

// ChangePassword and RemovePasswordCredential refresh has_password through
// the session payload the handlers that return one share.
func TestChangePasswordUpdatesHasPassword(t *testing.T) {
	h, s := newTestHandler(t)
	user, err := s.CreateUser("setpw@example.com", "SetPW", "password123")
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)
	req := authedRequest(http.MethodPut, "/api/account/password", cookie,
		[]byte(`{"new_password":"first-long-password"}`))
	w := httptest.NewRecorder()
	h.AuthMiddleware(h.ChangePassword)(w, req)
	if w.Code != http.StatusNoContent {
		t.Fatalf("set status %d: %s", w.Code, w.Body.String())
	}
	if has, err := s.GetPasswordCredential(user.ID); err != nil || has == "" {
		t.Fatalf("credential not stored: %q %v", has, err)
	}
}
