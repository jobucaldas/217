package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
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
