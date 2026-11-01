package handler_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"217/backend/internal/model"
)

func TestUpdateProfileValidatesAndNamesTheOtherSide(t *testing.T) {
	h, s := newTestHandler(t)
	owner := newUser(t, s, "profile-owner@example.com", "owner")
	partner := newUser(t, s, "profile-partner@example.com", "partner")
	ownerCookie := sessionCookie(t, s, owner.ID)
	partnerCookie := sessionCookie(t, s, partner.ID)

	put := func(cookie *http.Cookie, body string) (int, string) {
		w := call(t, h, h.UpdateProfile, http.MethodPut, "/api/account/profile", cookie, body)
		return w.Code, w.Body.String()
	}
	if code, _ := put(ownerCookie, `{"display_name":"`+strings.Repeat("a", 61)+`"}`); code != http.StatusBadRequest {
		t.Fatalf("long name: %d", code)
	}
	if code, _ := put(ownerCookie, `{"display_name":"a\u0007b"}`); code != http.StatusBadRequest {
		t.Fatalf("control character: %d", code)
	}
	for _, bad := range []string{"1981", "1981-13", "1899-12", "2999-01", "1981-1"} {
		if code, _ := put(ownerCookie, `{"birth_date":"`+bad+`"}`); code != http.StatusBadRequest {
			t.Fatalf("birth date %q: %d", bad, code)
		}
	}
	if code, _ := put(partnerCookie, `{"birth_date":"1980-01"}`); code != http.StatusForbidden {
		t.Fatalf("partner birth date: %d", code)
	}
	code, body := put(ownerCookie, `{"display_name":"  Ana  ","birth_date":"1981-11"}`)
	if code != http.StatusOK || !strings.Contains(body, `"display_name":"Ana"`) || !strings.Contains(body, `"birth_date":"1981-11"`) {
		t.Fatalf("set profile: %d %s", code, body)
	}
	// Omitted fields are kept.
	if code, body := put(ownerCookie, `{"display_name":"Ana B"}`); code != http.StatusOK || !strings.Contains(body, `"birth_date":"1981-11"`) {
		t.Fatalf("partial update: %d %s", code, body)
	}
	if code, body := put(partnerCookie, `{"display_name":"Bo"}`); code != http.StatusOK || !strings.Contains(body, `"display_name":"Bo"`) {
		t.Fatalf("partner display name: %d %s", code, body)
	}

	share, err := s.EnableShare(owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{owner.ID, partner.ID} {
		if _, err := s.RecordConsent(id, model.ConsentVersion); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := s.AcceptShare(partner.ID, share.InviteCode); err != nil {
		t.Fatal(err)
	}
	if state, _ := s.GetShareState(owner.ID); state.PartnerName != "Bo" {
		t.Fatalf("owner sees partner as %q", state.PartnerName)
	}
	if state, _ := s.GetShareState(partner.ID); state.OwnerName != "Ana B" {
		t.Fatalf("partner sees owner as %q", state.OwnerName)
	}
	if _, err := s.SendMessage(owner.ID, "hi"); err != nil {
		t.Fatal(err)
	}
	if msgs, _ := s.ListMessages(partner.ID); len(msgs) != 1 || msgs[0].FromName != "Ana B" {
		t.Fatalf("message from name: %+v", msgs)
	}
	// An empty display name falls back to the sign-in name.
	if code, _ := put(ownerCookie, `{"display_name":" "}`); code != http.StatusOK {
		t.Fatalf("reset: %d", code)
	}
	if msgs, _ := s.ListMessages(partner.ID); msgs[0].FromName != "profile-owner" {
		t.Fatalf("fallback name: %q", msgs[0].FromName)
	}

	export := call(t, h, h.ExportAccount, http.MethodGet, "/api/account/export", ownerCookie, "")
	if !strings.Contains(export.Body.String(), `"birth_date":"1981-11"`) {
		t.Fatalf("export lacks birth date: %s", export.Body.String())
	}
}

func TestCycleSuggestsStageToOwnerOnly(t *testing.T) {
	h, s := newTestHandler(t)
	owner := newUser(t, s, "suggest-owner@example.com", "owner")
	partner := newUser(t, s, "suggest-partner@example.com", "partner")
	ownerCookie := sessionCookie(t, s, owner.ID)
	now := time.Now().UTC()
	today := now.Format("2006-01-02")

	suggestion := func(cookie *http.Cookie) string {
		t.Helper()
		w := call(t, h, h.GetCycle, http.MethodGet, "/api/cycle?today="+today, cookie, "")
		if w.Code != http.StatusOK {
			t.Fatalf("cycle: %d %s", w.Code, w.Body.String())
		}
		var info struct {
			Suggested string `json:"suggested_stage"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &info); err != nil {
			t.Fatal(err)
		}
		return info.Suggested
	}

	if got := suggestion(ownerCookie); got != "" {
		t.Fatalf("no data suggested %q", got)
	}
	birth := now.AddDate(-50, 0, 0).Format("2006-01")
	if _, err := s.SetProfile(owner.ID, nil, &birth); err != nil {
		t.Fatal(err)
	}
	if got := suggestion(ownerCookie); got != model.StagePerimenopause {
		t.Fatalf("age 50 suggested %q", got)
	}
	// A period older than the prediction window still counts.
	if _, err := s.UpsertEntry(owner.ID, now.AddDate(-2, 0, 0).Format("2006-01-02"), model.UpsertRequest{Period: true}); err != nil {
		t.Fatal(err)
	}
	if got := suggestion(ownerCookie); got != model.StageMenopause {
		t.Fatalf("two years without a period suggested %q", got)
	}
	if _, err := s.SetStage(owner.ID, model.StageMenopause); err != nil {
		t.Fatal(err)
	}
	if got := suggestion(ownerCookie); got != "" {
		t.Fatalf("matching stage suggested %q", got)
	}
	if _, err := s.SetStage(owner.ID, model.StageCycling); err != nil {
		t.Fatal(err)
	}

	share, _ := s.EnableShare(owner.ID)
	for _, id := range []string{owner.ID, partner.ID} {
		if _, err := s.RecordConsent(id, model.ConsentVersion); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := s.AcceptShare(partner.ID, share.InviteCode); err != nil {
		t.Fatal(err)
	}
	if got := suggestion(sessionCookie(t, s, partner.ID)); got != "" {
		t.Fatalf("partner was suggested %q", got)
	}
}
