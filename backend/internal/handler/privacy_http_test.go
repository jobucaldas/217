package handler_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"217/backend/internal/model"
)

func TestDataEndpointsWaitForConsent(t *testing.T) {
	h, s := newTestHandler(t)
	user, err := s.LinkWorkOSIdentity("user_consent", "consent@example.com", "C", true)
	if err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, s, user.ID)
	list := func() int {
		w := httptest.NewRecorder()
		h.ConsentMiddleware(h.ListEntries)(w, authedRequest(http.MethodGet, "/api/entries", cookie, nil))
		return w.Code
	}
	if code := list(); code != http.StatusForbidden {
		t.Fatalf("before consent: %d, want 403", code)
	}

	w := httptest.NewRecorder()
	h.AuthMiddleware(h.RecordConsent)(w, authedRequest(http.MethodPut, "/api/account/consent", cookie, []byte(`{"version":0}`)))
	if w.Code != http.StatusConflict {
		t.Fatalf("outdated version: %d, want 409", w.Code)
	}

	w = httptest.NewRecorder()
	body := []byte(`{"version":` + jsonInt(model.ConsentVersion) + `}`)
	h.AuthMiddleware(h.RecordConsent)(w, authedRequest(http.MethodPut, "/api/account/consent", cookie, body))
	if w.Code != http.StatusOK {
		t.Fatalf("consent: %d %s", w.Code, w.Body.String())
	}
	var payload struct {
		Consent struct{ Required bool } `json:"consent"`
		User    struct {
			ConsentVersion int     `json:"consent_version"`
			ConsentedAt    *string `json:"consented_at"`
		} `json:"user"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload.Consent.Required || payload.User.ConsentVersion != model.ConsentVersion || payload.User.ConsentedAt == nil {
		t.Fatalf("consent not recorded: %s", w.Body.String())
	}
	if _, err := s.SetRole(user.ID, model.RoleOwner); err != nil {
		t.Fatal(err)
	}
	if code := list(); code != http.StatusOK {
		t.Fatalf("after consent: %d, want 200", code)
	}
}

func TestExportHasEverythingAboutTheCaller(t *testing.T) {
	h, s := newTestHandler(t)
	owner, _ := s.LinkWorkOSIdentity("user_exp_owner", "owner@example.com", "Owner", true)
	partner, _ := s.LinkWorkOSIdentity("user_exp_partner", "partner@example.com", "Partner", true)
	if _, err := s.SetRole(owner.ID, model.RoleOwner); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpsertEntry(owner.ID, "2026-09-01", model.UpsertRequest{Taken: model.BoolPtr(true), Notes: "first"}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpsertEntry(owner.ID, "2025-01-15", model.UpsertRequest{Period: true}); err != nil {
		t.Fatal(err)
	}
	share, _ := s.EnableShare(owner.ID)
	if _, err := s.AcceptShare(partner.ID, share.InviteCode); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreatePartnerNote(partner.ID, "hello"); err != nil {
		t.Fatal(err)
	}

	export := func(userID string) model.AccountExport {
		w := httptest.NewRecorder()
		h.AuthMiddleware(h.ExportAccount)(w, authedRequest(http.MethodGet, "/api/account/export", sessionCookie(t, s, userID), nil))
		if w.Code != http.StatusOK || !strings.Contains(w.Header().Get("Content-Disposition"), "attachment") {
			t.Fatalf("export: %d %v", w.Code, w.Header())
		}
		var out model.AccountExport
		if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
		return out
	}
	mine := export(owner.ID)
	if mine.User.Email != "owner@example.com" || len(mine.Entries) != 2 || mine.Entries[0].Date != "2025-01-15" ||
		len(mine.NotesReceived) != 1 || mine.NotesReceived[0].Body != "hello" || mine.Share.PartnerEmail != "partner@example.com" {
		t.Fatalf("owner export incomplete: %+v", mine)
	}
	theirs := export(partner.ID)
	if len(theirs.Entries) != 0 || len(theirs.NotesSent) != 1 || theirs.PartnerAlerts == nil {
		t.Fatalf("partner export must hold only the partner's own data: %+v", theirs)
	}
}

func jsonInt(n int) string {
	b, _ := json.Marshal(n)
	return string(b)
}
