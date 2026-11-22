package handler_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"217/backend/internal/handler"
	"217/backend/internal/model"
	"217/backend/internal/store"
	"217/backend/internal/synchub"
)

// spyStore counts the reads a sync warm makes; setting Store to nil makes
// any store call at all panic.
type spyStore struct {
	store.Store
	loads atomic.Int64
}

func (s *spyStore) GetSessionPrincipal(id string) (*model.User, time.Time, error) {
	s.loads.Add(1)
	return s.Store.GetSessionPrincipal(id)
}

type syncFixture struct {
	h       *handler.Handler
	s       store.Store // the wrapped store the handler uses
	hub     *synchub.Hub
	mem     *store.MemoryStore
	spy     *spyStore
	owner   *model.User
	partner *model.User
	ownerC  *http.Cookie
	partC   *http.Cookie
}

// newSyncFixture links a consenting owner and partner.
func newSyncFixture(t *testing.T) syncFixture {
	t.Helper()
	mem := store.NewMemoryStore()
	spy := &spyStore{Store: mem}
	hub := synchub.New()
	wrapped := synchub.Wrap(spy, hub)
	h := handler.New(wrapped)
	h.SetAppBaseURL("http://localhost:8080")
	h.SetSyncHub(hub)
	f := syncFixture{h: h, s: wrapped, hub: hub, mem: mem, spy: spy}
	var err error
	if f.owner, err = mem.CreateUser("owner@example.com", "Owner", "pw"); err != nil {
		t.Fatal(err)
	}
	if f.partner, err = mem.CreateUser("partner@example.com", "Partner", "pw"); err != nil {
		t.Fatal(err)
	}
	for _, u := range []*model.User{f.owner, f.partner} {
		if _, err := mem.RecordConsent(u.ID, model.ConsentVersion); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := mem.SetRole(f.owner.ID, model.RoleOwner); err != nil {
		t.Fatal(err)
	}
	share, err := mem.EnableShare(f.owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := mem.AcceptShare(f.partner.ID, share.InviteCode); err != nil {
		t.Fatal(err)
	}
	f.ownerC = sessionCookie(t, mem, f.owner.ID)
	f.partC = sessionCookie(t, mem, f.partner.ID)
	return f
}

type syncBody struct {
	ETag           string            `json:"etag"`
	UserID         string            `json:"user_id"`
	Role           string            `json:"role"`
	ShareActive    bool              `json:"share_active"`
	SubjectConsent bool              `json:"subject_consent"`
	Tags           map[string]string `json:"tags"`
}

func syncGet(f syncFixture, cookie *http.Cookie, ifNoneMatch string) *httptest.ResponseRecorder {
	req := authedRequest(http.MethodGet, "/api/sync/status", cookie, nil)
	if ifNoneMatch != "" {
		req.Header.Set("If-None-Match", ifNoneMatch)
	}
	w := httptest.NewRecorder()
	f.h.SyncStatus(w, req)
	return w
}

func syncStatus(t *testing.T, f syncFixture, cookie *http.Cookie) syncBody {
	t.Helper()
	w := syncGet(f, cookie, "")
	if w.Code != http.StatusOK {
		t.Fatalf("sync status: %d %s", w.Code, w.Body.String())
	}
	var b syncBody
	if err := json.Unmarshal(w.Body.Bytes(), &b); err != nil {
		t.Fatal(err)
	}
	if got := w.Header().Get("ETag"); got != `"`+b.ETag+`"` {
		t.Fatalf("ETag header %q, body etag %q", got, b.ETag)
	}
	return b
}

func syncCall(t *testing.T, fn http.HandlerFunc, method, path string, cookie *http.Cookie, body string) {
	t.Helper()
	w := httptest.NewRecorder()
	fn(w, authedRequest(method, path, cookie, []byte(body)))
	if w.Code >= 300 {
		t.Fatalf("%s %s: %d %s", method, path, w.Code, w.Body.String())
	}
}

func TestSyncStatusCachedPollTouchesNoStore(t *testing.T) {
	f := newSyncFixture(t)
	warm := syncStatus(t, f, f.ownerC)
	if f.spy.loads.Load() != 1 || warm.Role != model.RoleOwner || !warm.ShareActive || warm.Tags["calendar"] == "none" {
		t.Fatalf("warm: loads=%d %+v", f.spy.loads.Load(), warm)
	}

	f.spy.Store = nil // any store call now panics
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("cached poll called the store: %v", r)
		}
	}()
	bearer := authedRequest(http.MethodGet, "/api/sync/status", nil, nil)
	bearer.Header.Set("Authorization", "Bearer session-token-"+f.owner.ID)
	for i, inm := range []string{`"` + warm.ETag + `"`, `W/"` + warm.ETag + `"`, `"other", "` + warm.ETag + `"`, warm.ETag} {
		for range 25 {
			w := syncGet(f, f.ownerC, inm)
			if w.Code != http.StatusNotModified || w.Body.Len() != 0 || w.Header().Get("ETag") != `"`+warm.ETag+`"` {
				t.Fatalf("If-None-Match %d: %d %q", i, w.Code, w.Body.String())
			}
		}
	}
	bearer.Header.Set("If-None-Match", `"`+warm.ETag+`"`)
	w := httptest.NewRecorder()
	f.h.SyncStatus(w, bearer)
	if w.Code != http.StatusNotModified {
		t.Fatalf("bearer: %d", w.Code)
	}
	if w := syncGet(f, f.ownerC, `"stale"`); w.Code != http.StatusOK {
		t.Fatalf("stale etag: %d", w.Code)
	}
	if n := f.spy.loads.Load(); n != 1 {
		t.Fatalf("store loads after warm: %d", n)
	}
}

func TestSyncStatusTagsFollowWrites(t *testing.T) {
	f := newSyncFixture(t)
	s := f.s
	owner0, partner0 := syncStatus(t, f, f.ownerC), syncStatus(t, f, f.partC)

	if _, err := s.UpsertEntry(f.owner.ID, "2026-11-01", model.UpsertRequest{Taken: model.BoolPtr(true)}); err != nil {
		t.Fatal(err)
	}
	partner1 := syncStatus(t, f, f.partC)
	if partner1.Tags["calendar"] == partner0.Tags["calendar"] || partner1.ETag == partner0.ETag {
		t.Fatal("owner entry did not change the partner's calendar tag")
	}
	if partner1.Tags["inbox"] != partner0.Tags["inbox"] || partner1.Tags["account"] != partner0.Tags["account"] {
		t.Fatal("entry write changed unrelated tags")
	}

	if _, err := s.SendMessage(f.partner.ID, "hi"); err != nil {
		t.Fatal(err)
	}
	owner2, partner2 := syncStatus(t, f, f.ownerC), syncStatus(t, f, f.partC)
	if owner2.Tags["inbox"] == owner0.Tags["inbox"] || partner2.Tags["inbox"] == partner1.Tags["inbox"] {
		t.Fatal("message did not change both inbox tags")
	}

	if _, err := s.UpsertPartnerAlerts(f.partner.ID, model.PartnerAlertPreference{}); err != nil {
		t.Fatal(err)
	}
	if syncStatus(t, f, f.partC).Tags["prefs"] == partner2.Tags["prefs"] {
		t.Fatal("alert prefs did not change the prefs tag")
	}
}

func TestSyncStatusRevocation(t *testing.T) {
	cleared := func(w *httptest.ResponseRecorder) bool {
		return strings.Contains(w.Header().Get("Set-Cookie"), "217_session=;")
	}
	t.Run("revoke share", func(t *testing.T) {
		f := newSyncFixture(t)
		syncStatus(t, f, f.partC)
		syncCall(t, f.h.AuthMiddleware(f.h.RevokeShare), http.MethodPost, "/api/share/revoke", f.ownerC, "")
		p := syncStatus(t, f, f.partC)
		if p.ShareActive || p.Tags["calendar"] != "none" || syncStatus(t, f, f.ownerC).ShareActive {
			t.Fatalf("after revoke: %+v", p)
		}
	})
	t.Run("owner withdraws consent", func(t *testing.T) {
		f := newSyncFixture(t)
		syncStatus(t, f, f.ownerC)
		syncStatus(t, f, f.partC)
		syncCall(t, f.h.AuthMiddleware(f.h.WithdrawConsent), http.MethodDelete, "/api/account/consent", f.ownerC, "")
		if w := syncGet(f, f.ownerC, ""); w.Code != http.StatusForbidden || !strings.Contains(w.Body.String(), "consent required") {
			t.Fatalf("owner: %d %s", w.Code, w.Body.String())
		}
		if p := syncStatus(t, f, f.partC); p.SubjectConsent || p.Tags["calendar"] != "none" {
			t.Fatalf("partner still sees the calendar: %+v", p)
		}
	})
	t.Run("partner withdraws consent", func(t *testing.T) {
		f := newSyncFixture(t)
		syncStatus(t, f, f.partC)
		syncCall(t, f.h.AuthMiddleware(f.h.WithdrawConsent), http.MethodDelete, "/api/account/consent", f.partC, "")
		if w := syncGet(f, f.partC, ""); w.Code != http.StatusForbidden {
			t.Fatalf("partner: %d", w.Code)
		}
	})
	t.Run("delete account", func(t *testing.T) {
		f := newSyncFixture(t)
		syncStatus(t, f, f.ownerC)
		syncStatus(t, f, f.partC)
		syncCall(t, f.h.AuthMiddleware(f.h.DeleteAccount), http.MethodDelete, "/api/account", f.ownerC, "")
		if w := syncGet(f, f.ownerC, ""); w.Code != http.StatusUnauthorized || !cleared(w) {
			t.Fatalf("deleted owner: %d %v", w.Code, w.Header())
		}
		if p := syncStatus(t, f, f.partC); p.ShareActive || p.Tags["calendar"] != "none" {
			t.Fatalf("partner after owner deletion: %+v", p)
		}
	})
	t.Run("logout", func(t *testing.T) {
		f := newSyncFixture(t)
		syncStatus(t, f, f.ownerC)
		syncCall(t, f.h.Logout, http.MethodPost, "/api/auth/logout", f.ownerC, "")
		if w := syncGet(f, f.ownerC, ""); w.Code != http.StatusUnauthorized {
			t.Fatalf("after logout: %d", w.Code)
		}
	})
	t.Run("session expiry", func(t *testing.T) {
		f := newSyncFixture(t)
		syncStatus(t, f, f.ownerC)
		f.hub.SetClock(func() time.Time { return time.Now().Add(2 * time.Hour) })
		f.spy.Store = nil
		if w := syncGet(f, f.ownerC, ""); w.Code != http.StatusUnauthorized || !cleared(w) {
			t.Fatalf("expired: %d", w.Code)
		}
	})
	t.Run("role switch", func(t *testing.T) {
		f := newSyncFixture(t)
		syncCall(t, f.h.AuthMiddleware(f.h.RevokeShare), http.MethodPost, "/api/share/revoke", f.ownerC, "")
		if p := syncStatus(t, f, f.partC); p.Role != model.RolePartner || p.Tags["calendar"] != "none" {
			t.Fatalf("partner before switch: %+v", p)
		}
		syncCall(t, f.h.AuthMiddleware(f.h.SetRole), http.MethodPut, "/api/account/role", f.partC, `{"role":"owner"}`)
		if p := syncStatus(t, f, f.partC); p.Role != model.RoleOwner || p.Tags["calendar"] == "none" {
			t.Fatalf("after switch: %+v", p)
		}
	})
}

func TestSyncStatusRejects(t *testing.T) {
	f := newSyncFixture(t)
	syncStatus(t, f, f.ownerC)
	if w := syncGet(f, nil, ""); w.Code != http.StatusUnauthorized {
		t.Fatalf("no token: %d", w.Code)
	}
	unknown := &http.Cookie{Name: "217_session", Value: "nope"}
	var last int
	for range 31 {
		last = syncGet(f, unknown, "").Code
	}
	if last != http.StatusTooManyRequests {
		t.Fatalf("uncached polls not rate limited: %d", last)
	}
	// Cached sessions are answered before the limiter.
	if w := syncGet(f, f.ownerC, ""); w.Code != http.StatusOK {
		t.Fatalf("cached owner was limited: %d", w.Code)
	}
	if w := syncGet(f, f.partC, ""); w.Code != http.StatusTooManyRequests {
		t.Fatalf("cold partner should be limited: %d", w.Code)
	}
}

type failingStore struct {
	store.Store
	sessionErr error
	entryErr   error
	revokeErr  error
}

func (f *failingStore) GetSessionPrincipal(id string) (*model.User, time.Time, error) {
	if f.sessionErr != nil {
		return nil, time.Time{}, f.sessionErr
	}
	return f.Store.GetSessionPrincipal(id)
}

func (f *failingStore) GetEntry(userID, date string) (*model.Entry, error) {
	if f.entryErr != nil {
		return nil, f.entryErr
	}
	return f.Store.GetEntry(userID, date)
}

func (f *failingStore) RevokeShare(ownerID string) (*model.ShareState, error) {
	if f.revokeErr != nil {
		_, _ = f.Store.RevokeShare(ownerID)
		return nil, f.revokeErr
	}
	return f.Store.RevokeShare(ownerID)
}

func TestStorageErrorsReturn500NotAuthOrNotFound(t *testing.T) {
	mem := store.NewMemoryStore()
	fs := &failingStore{Store: mem}
	hub := synchub.New()
	wrapped := synchub.Wrap(fs, hub)
	h := handler.New(wrapped)
	h.SetAppBaseURL("http://localhost:8080")
	h.SetSyncHub(hub)

	owner, err := mem.CreateUser("err-owner@example.com", "Owner", "pw")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := mem.RecordConsent(owner.ID, model.ConsentVersion); err != nil {
		t.Fatal(err)
	}
	if _, err := mem.SetRole(owner.ID, model.RoleOwner); err != nil {
		t.Fatal(err)
	}
	cookie := sessionCookie(t, mem, owner.ID)

	// DB error during cold SyncStatus load must return 500 and NOT clear the cookie.
	fs.sessionErr = store.ErrEntryNotFound // arbitrary non-ErrSessionNotFound error
	req := authedRequest(http.MethodGet, "/api/sync/status", cookie, nil)
	w := httptest.NewRecorder()
	h.SyncStatus(w, req)
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("SyncStatus DB error: got %d, want 500", w.Code)
	}
	if strings.Contains(w.Header().Get("Set-Cookie"), "217_session=;") {
		t.Fatalf("SyncStatus DB error must not clear session cookie: %v", w.Header())
	}
	fs.sessionErr = nil

	// DB error during GetEntry must return 500, not 404.
	fs.entryErr = store.ErrSessionNotFound // arbitrary non-ErrEntryNotFound error
	entryReq := authedRequest(http.MethodGet, "/api/entries/2026-11-01", cookie, nil)
	entryReq.SetPathValue("date", "2026-11-01")
	w2 := httptest.NewRecorder()
	h.AuthMiddleware(h.GetEntry)(w2, entryReq)
	if w2.Code != http.StatusInternalServerError {
		t.Fatalf("GetEntry DB error: got %d, want 500", w2.Code)
	}
	fs.entryErr = nil

	// Missing entry still returns 404.
	w3 := httptest.NewRecorder()
	h.AuthMiddleware(h.GetEntry)(w3, entryReq)
	if w3.Code != http.StatusNotFound {
		t.Fatalf("GetEntry missing: got %d, want 404", w3.Code)
	}
}

func TestShareInviteAndRevokeErrorFlushAndBumpAccountTag(t *testing.T) {
	mem := store.NewMemoryStore()
	fs := &failingStore{Store: mem}
	hub := synchub.New()
	wrapped := synchub.Wrap(fs, hub)
	h := handler.New(wrapped)
	h.SetAppBaseURL("http://localhost:8080")
	h.SetSyncHub(hub)

	owner, _ := mem.CreateUser("share-owner@example.com", "Owner", "pw")
	partner, _ := mem.CreateUser("share-partner@example.com", "Partner", "pw")
	_, _ = mem.RecordConsent(owner.ID, model.ConsentVersion)
	_, _ = mem.RecordConsent(partner.ID, model.ConsentVersion)
	_, _ = mem.SetRole(owner.ID, model.RoleOwner)
	ownerC := sessionCookie(t, mem, owner.ID)
	partC := sessionCookie(t, mem, partner.ID)
	f := syncFixture{h: h, s: wrapped, hub: hub, mem: mem, owner: owner, partner: partner, ownerC: ownerC, partC: partC}

	before := syncStatus(t, f, ownerC)
	share, err := wrapped.EnableShare(owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	afterEnable := syncStatus(t, f, ownerC)
	if afterEnable.Tags["account"] == before.Tags["account"] {
		t.Fatal("EnableShare must change owner's account tag (none -> open)")
	}
	if _, err := wrapped.AcceptShare(partner.ID, share.InviteCode); err != nil {
		t.Fatal(err)
	}
	_ = syncStatus(t, f, partC) // warm partner cache

	// Even if RevokeShare returns an error after committing, hub must flush.
	fs.revokeErr = store.ErrEntryNotFound
	if _, err := wrapped.RevokeShare(owner.ID); err == nil {
		t.Fatal("expected injected revoke error")
	}
	fs.revokeErr = nil
	afterRevoke := syncStatus(t, f, partC)
	if afterRevoke.ShareActive || afterRevoke.Tags["calendar"] != "none" {
		t.Fatalf("RevokeShare error must still flush partner cache: %+v", afterRevoke)
	}
}
