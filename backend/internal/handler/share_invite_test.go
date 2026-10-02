package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"217/backend/internal/model"
	"217/backend/internal/store"
)

func TestEnableShareReturnsInviteURL(t *testing.T) {
	s := store.NewMemoryStore()
	owner, err := s.CreateUser("owner@example.com", "Owner", "password123")
	if err != nil {
		t.Fatal(err)
	}
	h := New(s)
	h.SetAppBaseURL("https://217.example.com/")

	req := httptest.NewRequest(http.MethodPost, "/api/share/enable", nil)
	req = req.WithContext(context.WithValue(req.Context(), userIDKey, owner.ID))
	w := httptest.NewRecorder()
	h.EnableShare(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status %d body %s", w.Code, w.Body.String())
	}
	var state model.ShareState
	if err := json.Unmarshal(w.Body.Bytes(), &state); err != nil {
		t.Fatal(err)
	}
	want := "https://217.example.com/?invite=" + state.InviteCode
	if state.InviteCode == "" || state.InviteURL != want {
		t.Fatalf("invite_url = %q, want %q", state.InviteURL, want)
	}

	payload := h.sessionPayload(owner)
	if got := payload["share"].(*model.ShareState).InviteURL; got != want {
		t.Fatalf("session invite_url = %q, want %q", got, want)
	}
}

func TestInviteURLOnlyForOpenInvites(t *testing.T) {
	h := New(store.NewMemoryStore())
	h.SetAppBaseURL("https://217.example.com")
	for _, state := range []*model.ShareState{
		{Status: model.ShareActive, InviteCode: "ABCD"},
		{Status: model.ShareRevoked, InviteCode: "ABCD"},
		{Status: model.ShareOpen},
	} {
		if got := h.withInviteURL(state).InviteURL; got != "" {
			t.Fatalf("status %s code %q: invite_url = %q", state.Status, state.InviteCode, got)
		}
	}
	if h.withInviteURL(nil) != nil {
		t.Fatal("nil state should stay nil")
	}
	noBase := New(store.NewMemoryStore())
	if got := noBase.withInviteURL(&model.ShareState{Status: model.ShareOpen, InviteCode: "ABCD"}).InviteURL; got != "" {
		t.Fatalf("without APP_BASE_URL invite_url = %q", got)
	}
}

func TestAcceptShareIsRateLimited(t *testing.T) {
	s := store.NewMemoryStore()
	guesser, err := s.CreateUser("guesser@example.com", "Guesser", "password123")
	if err != nil {
		t.Fatal(err)
	}
	h := New(s)

	status := func() int {
		req := httptest.NewRequest(http.MethodPost, "/api/share/accept", strings.NewReader(`{"code":"WRONG234"}`))
		req = req.WithContext(context.WithValue(req.Context(), userIDKey, guesser.ID))
		w := httptest.NewRecorder()
		h.AcceptShare(w, req)
		return w.Code
	}
	for i := 0; i < inviteAcceptLimit; i++ {
		if got := status(); got != http.StatusBadRequest {
			t.Fatalf("attempt %d: status %d, want 400 for a wrong code", i+1, got)
		}
	}
	if got := status(); got != http.StatusTooManyRequests {
		t.Fatalf("attempt over the limit: status %d, want 429", got)
	}
}

func TestClientIPIgnoresSpoofedForwardedFor(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "10.0.0.5:4321"
	// A client prepends a fake address; the proxy appends the real one.
	req.Header.Set("X-Forwarded-For", "1.2.3.4, 203.0.113.9")
	if got := clientIP(req); got != "203.0.113.9" {
		t.Fatalf("clientIP = %q, want the proxy-appended address", got)
	}
	req.Header.Del("X-Forwarded-For")
	if got := clientIP(req); got != "10.0.0.5" {
		t.Fatalf("clientIP without XFF = %q", got)
	}
}
