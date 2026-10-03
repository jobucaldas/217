package handler_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"217/backend/internal/handler"
	"217/backend/internal/model"
	"217/backend/internal/store"
)

func call(t *testing.T, h *handler.Handler, fn http.HandlerFunc, method, path string, cookie *http.Cookie, body string, pathValues ...string) *httptest.ResponseRecorder {
	t.Helper()
	req := authedRequest(method, path, cookie, []byte(body))
	for i := 0; i+1 < len(pathValues); i += 2 {
		req.SetPathValue(pathValues[i], pathValues[i+1])
	}
	w := httptest.NewRecorder()
	h.AuthMiddleware(fn)(w, req)
	return w
}

func newUser(t *testing.T, s *store.MemoryStore, email, role string) *model.User {
	t.Helper()
	user, err := s.CreateUser(email, strings.Split(email, "@")[0], "pw")
	if err != nil {
		t.Fatal(err)
	}
	if role != "" {
		if _, err := s.SetRole(user.ID, role); err != nil {
			t.Fatal(err)
		}
	}
	return user
}

func TestNewUserMustChooseRoleBeforeCalendar(t *testing.T) {
	h, s := newTestHandler(t)
	user := newUser(t, s, "new@example.com", "")
	cookie := sessionCookie(t, s, user.ID)

	session := call(t, h, h.CurrentSession, http.MethodGet, "/api/auth/session", cookie, "")
	if !strings.Contains(session.Body.String(), `"role":""`) {
		t.Fatalf("expected unset role in session: %s", session.Body.String())
	}
	if w := call(t, h, h.ListEntries, http.MethodGet, "/api/entries?year=2026&month=10", cookie, ""); w.Code != http.StatusForbidden || !strings.Contains(w.Body.String(), "role not chosen") {
		t.Fatalf("list entries without role: %d %s", w.Code, w.Body.String())
	}
	if w := call(t, h, h.EnableShare, http.MethodPost, "/api/share/enable", cookie, ""); w.Code != http.StatusForbidden {
		t.Fatalf("enable share without role: %d", w.Code)
	}
	if w := call(t, h, h.SetRole, http.MethodPut, "/api/account/role", cookie, `{"role":"boss"}`); w.Code != http.StatusBadRequest {
		t.Fatalf("invalid role: %d", w.Code)
	}
	w := call(t, h, h.SetRole, http.MethodPut, "/api/account/role", cookie, `{"role":"owner"}`)
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"role":"owner"`) || !strings.Contains(w.Body.String(), `"can_edit_calendar":true`) {
		t.Fatalf("set owner: %d %s", w.Code, w.Body.String())
	}
}

func TestOwnersCannotJoinAndPartnersCannotShare(t *testing.T) {
	h, s := newTestHandler(t)
	owner := newUser(t, s, "girl@example.com", "owner")
	other := newUser(t, s, "other@example.com", "owner")
	partner := newUser(t, s, "bf@example.com", "partner")
	ownerCookie := sessionCookie(t, s, owner.ID)
	otherCookie := sessionCookie(t, s, other.ID)
	partnerCookie := sessionCookie(t, s, partner.ID)

	// A partner who has not joined yet sees "none", not "revoked".
	state, _ := s.GetShareState(partner.ID)
	if state.Status != model.ShareNone || state.CanEditCalendar {
		t.Fatalf("fresh partner state: %+v", state)
	}
	if w := call(t, h, h.EnableShare, http.MethodPost, "/api/share/enable", partnerCookie, ""); w.Code != http.StatusForbidden {
		t.Fatalf("partner enable share: %d", w.Code)
	}

	enabled, err := s.EnableShare(owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	body := `{"code":"` + enabled.InviteCode + `"}`
	if w := call(t, h, h.AcceptShare, http.MethodPost, "/api/share/accept", otherCookie, body); w.Code != http.StatusBadRequest || !strings.Contains(w.Body.String(), "calendar owners") {
		t.Fatalf("owner accept: %d %s", w.Code, w.Body.String())
	}
	if w := call(t, h, h.AcceptShare, http.MethodPost, "/api/share/accept", partnerCookie, body); w.Code != http.StatusOK {
		t.Fatalf("partner accept: %d %s", w.Code, w.Body.String())
	}

	// Roles are locked while linked.
	if w := call(t, h, h.SetRole, http.MethodPut, "/api/account/role", ownerCookie, `{"role":"partner"}`); w.Code != http.StatusConflict {
		t.Fatalf("owner role switch while shared: %d", w.Code)
	}
	if w := call(t, h, h.SetRole, http.MethodPut, "/api/account/role", partnerCookie, `{"role":"owner"}`); w.Code != http.StatusConflict {
		t.Fatalf("partner role switch while shared: %d", w.Code)
	}
	// Re-sending the current role is fine.
	if w := call(t, h, h.SetRole, http.MethodPut, "/api/account/role", partnerCookie, `{"role":"partner"}`); w.Code != http.StatusOK {
		t.Fatalf("same role: %d", w.Code)
	}

	if _, err := s.RevokeShare(owner.ID); err != nil {
		t.Fatal(err)
	}
	if w := call(t, h, h.SetRole, http.MethodPut, "/api/account/role", partnerCookie, `{"role":"owner"}`); w.Code != http.StatusOK {
		t.Fatalf("role switch after revoke: %d %s", w.Code, w.Body.String())
	}
}

func TestInviteLinkMakesUnsetUserAPartner(t *testing.T) {
	_, s := newTestHandler(t)
	owner := newUser(t, s, "girl@example.com", "owner")
	fresh := newUser(t, s, "fresh@example.com", "")
	enabled, err := s.EnableShare(owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.AcceptShare(fresh.ID, enabled.InviteCode); err != nil {
		t.Fatal(err)
	}
	reloaded, _ := s.GetUserByID(fresh.ID)
	if reloaded.Role != model.RolePartner {
		t.Fatalf("expected partner, got %q", reloaded.Role)
	}
}

func TestCycleEndpointSharedWithPartner(t *testing.T) {
	h, s := newTestHandler(t)
	owner := newUser(t, s, "girl@example.com", "owner")
	partner := newUser(t, s, "bf@example.com", "partner")
	ownerCookie := sessionCookie(t, s, owner.ID)
	partnerCookie := sessionCookie(t, s, partner.ID)

	today := time.Now().UTC()
	for _, back := range []int{60, 59, 58, 32, 31, 30, 4, 3} {
		d := today.AddDate(0, 0, -back).Format("2006-01-02")
		w := call(t, h, h.UpsertEntry, http.MethodPost, "/api/entries/"+d, ownerCookie, `{"taken":true,"period":true}`, "date", d)
		if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"period":true`) {
			t.Fatalf("upsert period: %d %s", w.Code, w.Body.String())
		}
	}

	if w := call(t, h, h.GetCycle, http.MethodGet, "/api/cycle", partnerCookie, ""); w.Code != http.StatusForbidden {
		t.Fatalf("unlinked partner cycle: %d", w.Code)
	}
	enabled, _ := s.EnableShare(owner.ID)
	if _, err := s.AcceptShare(partner.ID, enabled.InviteCode); err != nil {
		t.Fatal(err)
	}

	w := call(t, h, h.GetCycle, http.MethodGet, "/api/cycle?today="+today.Format("2006-01-02"), partnerCookie, "")
	if w.Code != http.StatusOK {
		t.Fatalf("cycle: %d %s", w.Code, w.Body.String())
	}
	var info model.CycleInfo
	if err := json.Unmarshal(w.Body.Bytes(), &info); err != nil {
		t.Fatal(err)
	}
	if info.Estimated || info.CycleLength != 28 || len(info.PeriodStarts) != 3 || len(info.Predictions) != 3 {
		t.Fatalf("unexpected cycle info: %+v", info)
	}
	want := today.AddDate(0, 0, -4+28).Format("2006-01-02")
	if info.Predictions[0].PeriodStart != want {
		t.Fatalf("first prediction %s, want %s", info.Predictions[0].PeriodStart, want)
	}
	if w := call(t, h, h.GetCycle, http.MethodGet, "/api/cycle?today=1999-01-01", ownerCookie, ""); w.Code != http.StatusBadRequest {
		t.Fatalf("out of range today: %d", w.Code)
	}
}

func TestPartnerAlertPreferences(t *testing.T) {
	h, s := newTestHandler(t)
	owner := newUser(t, s, "girl@example.com", "owner")
	partner := newUser(t, s, "bf@example.com", "partner")
	ownerCookie := sessionCookie(t, s, owner.ID)
	partnerCookie := sessionCookie(t, s, partner.ID)

	if w := call(t, h, h.GetPartnerAlerts, http.MethodGet, "/api/partner-alerts", ownerCookie, ""); w.Code != http.StatusForbidden {
		t.Fatalf("owner partner alerts: %d", w.Code)
	}
	w := call(t, h, h.GetPartnerAlerts, http.MethodGet, "/api/partner-alerts", partnerCookie, "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"pms_time":"09:00"`) || !strings.Contains(w.Body.String(), `"pill_enabled":false`) {
		t.Fatalf("defaults: %d %s", w.Code, w.Body.String())
	}
	if w := call(t, h, h.UpsertPartnerAlerts, http.MethodPut, "/api/partner-alerts", partnerCookie, `{"pms_enabled":true,"pms_time":"25:00","pill_enabled":false,"pill_time":"21:00"}`); w.Code != http.StatusBadRequest {
		t.Fatalf("bad time: %d", w.Code)
	}
	w = call(t, h, h.UpsertPartnerAlerts, http.MethodPut, "/api/partner-alerts", partnerCookie, `{"pms_enabled":true,"pms_time":"08:30","pill_enabled":true,"pill_time":"22:15"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("save: %d %s", w.Code, w.Body.String())
	}
	pref, _ := s.GetPartnerAlerts(partner.ID)
	if !pref.PMSEnabled || pref.PMSTime != "08:30" || !pref.PillEnabled || pref.PillTime != "22:15" {
		t.Fatalf("saved: %+v", pref)
	}
}
