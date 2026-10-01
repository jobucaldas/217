package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
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
