package handler_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"217/backend/internal/auth"
)

func TestAccountDeleteAndShareHTTP(t *testing.T) {
	h, s := newTestHandler(t)
	owner, err := s.CreateUser("girl@example.com", "Girl", "pw")
	if err != nil {
		t.Fatal(err)
	}
	partner, err := s.CreateUser("bf@example.com", "Boyfriend", "pw")
	if err != nil {
		t.Fatal(err)
	}
	ownerCookie := sessionCookie(t, s, owner.ID)
	partnerCookie := sessionCookie(t, s, partner.ID)

	enableReq := authedRequest(http.MethodPost, "/api/share/enable", ownerCookie, nil)
	enableW := httptest.NewRecorder()
	h.AuthMiddleware(h.EnableShare)(enableW, enableReq)
	if enableW.Code != http.StatusOK {
		t.Fatalf("enable: %d %s", enableW.Code, enableW.Body.String())
	}
	var share map[string]interface{}
	if err := json.Unmarshal(enableW.Body.Bytes(), &share); err != nil {
		t.Fatal(err)
	}
	code, _ := share["invite_code"].(string)
	if code == "" {
		t.Fatalf("missing invite code: %v", share)
	}

	acceptBody := []byte(`{"code":"` + code + `"}`)
	acceptReq := authedRequest(http.MethodPost, "/api/share/accept", partnerCookie, acceptBody)
	acceptW := httptest.NewRecorder()
	h.AuthMiddleware(h.AcceptShare)(acceptW, acceptReq)
	if acceptW.Code != http.StatusOK {
		t.Fatalf("accept: %d %s", acceptW.Code, acceptW.Body.String())
	}

	upsertReq := authedRequest(http.MethodPost, "/api/entries/2026-10-01", partnerCookie, []byte(`{"taken":true}`))
	upsertW := httptest.NewRecorder()
	h.AuthMiddleware(h.UpsertEntry)(upsertW, upsertReq)
	if upsertW.Code != http.StatusForbidden {
		t.Fatalf("partner upsert expected 403, got %d", upsertW.Code)
	}

	noteReq := authedRequest(http.MethodPost, "/api/partner-notes", partnerCookie, []byte(`{"body":"hi"}`))
	noteW := httptest.NewRecorder()
	h.AuthMiddleware(h.CreatePartnerNote)(noteW, noteReq)
	if noteW.Code != http.StatusCreated {
		t.Fatalf("note: %d %s", noteW.Code, noteW.Body.String())
	}

	inboxReq := authedRequest(http.MethodGet, "/api/inbox", ownerCookie, nil)
	inboxW := httptest.NewRecorder()
	h.AuthMiddleware(h.ListInbox)(inboxW, inboxReq)
	if inboxW.Code != http.StatusOK || !strings.Contains(inboxW.Body.String(), "hi") {
		t.Fatalf("inbox: %d %s", inboxW.Code, inboxW.Body.String())
	}

	revokeReq := authedRequest(http.MethodPost, "/api/share/revoke", ownerCookie, nil)
	revokeW := httptest.NewRecorder()
	h.AuthMiddleware(h.RevokeShare)(revokeW, revokeReq)
	if revokeW.Code != http.StatusOK {
		t.Fatalf("revoke: %d %s", revokeW.Code, revokeW.Body.String())
	}

	delReq := authedRequest(http.MethodDelete, "/api/account", partnerCookie, nil)
	delW := httptest.NewRecorder()
	h.AuthMiddleware(h.DeleteAccount)(delW, delReq)
	if delW.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", delW.Code, delW.Body.String())
	}
	if _, err := s.GetUserByID(partner.ID); err == nil {
		t.Fatal("partner should be deleted")
	}
}

func TestDeleteAccountRemovesWorkOSUserFirst(t *testing.T) {
	h, s := newTestHandler(t)
	provider := &fakeOAuthProvider{}
	h.SetOAuthProvider(provider)

	user, err := s.LinkWorkOSIdentity("user_workos_delete_1", "deleteme@example.com", "Delete Me", true)
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)

	req := authedRequest(http.MethodDelete, "/api/account", cookie, nil)
	w := httptest.NewRecorder()
	h.AuthMiddleware(h.DeleteAccount)(w, req)
	if w.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", w.Code, w.Body.String())
	}
	if len(provider.deletedIDs) != 1 || provider.deletedIDs[0] != "user_workos_delete_1" {
		t.Fatalf("expected WorkOS delete of subject, got %#v", provider.deletedIDs)
	}
	cleared := false
	for _, c := range w.Result().Cookies() {
		if c.Name == "217_session" && c.MaxAge < 0 {
			cleared = true
		}
	}
	if !cleared {
		t.Fatal("expected session cookie cleared")
	}
	if _, err := s.GetUserByID(user.ID); err == nil {
		t.Fatal("local user should be gone after WorkOS delete")
	}
	subject, err := s.WorkOSSubject(user.ID)
	if err != nil || subject != "" {
		t.Fatalf("expected no local WorkOS subject after delete, got %q err=%v", subject, err)
	}
}

func TestDeleteAccountFailsClosedWhenWorkOSDeleteFails(t *testing.T) {
	h, s := newTestHandler(t)
	provider := &fakeOAuthProvider{deleteErr: fmt.Errorf("workos unavailable")}
	h.SetOAuthProvider(provider)

	user, err := s.LinkWorkOSIdentity("user_workos_keep_1", "keepme@example.com", "Keep Me", true)
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)

	req := authedRequest(http.MethodDelete, "/api/account", cookie, nil)
	w := httptest.NewRecorder()
	h.AuthMiddleware(h.DeleteAccount)(w, req)
	if w.Code != http.StatusBadGateway {
		t.Fatalf("expected 502 fail-closed, got %d %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "failed to delete WorkOS user") {
		t.Fatalf("expected clear WorkOS error, got %s", w.Body.String())
	}
	if _, err := s.GetUserByID(user.ID); err != nil {
		t.Fatalf("local user must remain when WorkOS delete fails: %v", err)
	}
	subject, err := s.WorkOSSubject(user.ID)
	if err != nil || subject != "user_workos_keep_1" {
		t.Fatalf("subject must remain, got %q err=%v", subject, err)
	}
}

type authOnlyProvider struct{}

func (authOnlyProvider) AuthCodeURL(state, codeChallenge, nonce string) string {
	return "https://example.test/auth"
}
func (authOnlyProvider) Exchange(context.Context, string, string, string) (*auth.OAuthUserInfo, error) {
	return nil, fmt.Errorf("unused")
}

func TestDeleteAccountFailsClosedWithoutWorkOSDeleter(t *testing.T) {
	h, s := newTestHandler(t)
	h.SetOAuthProvider(authOnlyProvider{})

	user, err := s.LinkWorkOSIdentity("user_workos_nodeleter", "nodeleter@example.com", "No Deleter", true)
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)
	req := authedRequest(http.MethodDelete, "/api/account", cookie, nil)
	w := httptest.NewRecorder()
	h.AuthMiddleware(h.DeleteAccount)(w, req)
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d %s", w.Code, w.Body.String())
	}
	if _, err := s.GetUserByID(user.ID); err != nil {
		t.Fatalf("local user must remain: %v", err)
	}
}

func TestSessionIncludesShare(t *testing.T) {
	h, s := newTestHandler(t)
	user, err := s.CreateUser("sess@example.com", "Sess", "pw")
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)
	req := authedRequest(http.MethodGet, "/api/auth/session", cookie, nil)
	w := httptest.NewRecorder()
	h.CurrentSession(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("session: %d", w.Code)
	}
	var payload map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload["share"] == nil {
		t.Fatalf("expected share in session: %v", payload)
	}
}
