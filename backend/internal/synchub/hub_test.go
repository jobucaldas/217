package synchub

import (
	"reflect"
	"testing"
	"time"

	"217/backend/internal/model"
	"217/backend/internal/store"
)

// Every Store method must be classified: reads (and writes that change no
// synced state) pass through, the rest are overridden in wrap.go.
var (
	readOnly = []string{
		"CreateUser", "GetUserByEmail", "GetUserByID", "WorkOSSubject", "PurgeExpired",
		"GetEntry", "ListEntries", "ListAllEntries", "GetStats", "ListPeriodDays",
		"GetReminderPreference", "SavePushSubscription", "DeletePushSubscription", "CountPushSubscriptions",
		"ListReminderTargets", "ClaimReminderDelivery", "FinishReminderDelivery",
		"CreateOAuthAttempt", "ConsumeOAuthAttempt",
		"CreateSession", "GetUserBySession", "GetSessionPrincipal", "SessionCreatedAt",
		"CreateDeviceSession", "SetDeviceChallenge", "ConsumeDeviceChallenge", "ListDeviceKeys",
		"GetShareState", "CalendarSubjectID", "ActivePeer", "GetPartnerAlerts",
		"ListMessages", "ListAccountShares", "ListAccountSubscriptions", "Close",
	}
	hooked = []string{
		"UpsertEntry", "DeleteEntry", "SetStage", "SetProfile", "SendMessage", "MarkMessageRead",
		"UpsertPartnerAlerts", "UpsertReminderPreference",
		"RecordConsent", "SetRole", "EnableShare", "RevokeShare", "AcceptShare", "DeleteUser",
		"DeleteSession", "DeleteSessionAndDevice", "DeleteAllSessionsForUser", "CreateDeviceKey", "LinkWorkOSIdentity",
	}
)

func TestEveryStoreMethodClassified(t *testing.T) {
	known := map[string]bool{}
	for _, m := range append(append([]string{}, readOnly...), hooked...) {
		known[m] = true
	}
	iface := reflect.TypeOf((*store.Store)(nil)).Elem()
	for i := 0; i < iface.NumMethod(); i++ {
		if name := iface.Method(i).Name; !known[name] {
			t.Errorf("store.Store.%s is not classified for the sync hub (wrap.go, hub_test.go)", name)
		}
	}
	for _, name := range append(append([]string{}, readOnly...), hooked...) {
		if _, ok := iface.MethodByName(name); !ok {
			t.Errorf("%s is listed but is not a store method", name)
		}
	}
	if len(known) != len(readOnly)+len(hooked) {
		t.Error("a method is listed twice")
	}
}

type fixture struct {
	mem   *store.MemoryStore
	hub   *Hub
	s     store.Store
	owner *model.User
	token string
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	mem := store.NewMemoryStore()
	hub := New()
	s := Wrap(mem, hub)
	owner, err := mem.CreateUser("owner@example.com", "Owner", "pw")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := mem.SetRole(owner.ID, model.RoleOwner); err != nil {
		t.Fatal(err)
	}
	if _, err := mem.RecordConsent(owner.ID, model.ConsentVersion); err != nil {
		t.Fatal(err)
	}
	if err := mem.CreateSession(owner.ID, "owner-token", time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	return fixture{mem: mem, hub: hub, s: s, owner: owner, token: "owner-token"}
}

// flushingStore runs a Flush in the middle of a cache warm.
type flushingStore struct {
	store.Store
	hub       *Hub
	remaining int
	onRead    func()
}

func (f *flushingStore) GetSessionPrincipal(id string) (*model.User, time.Time, error) {
	u, exp, err := f.Store.GetSessionPrincipal(id)
	if f.remaining != 0 {
		if f.remaining > 0 {
			f.remaining--
		}
		if f.onRead != nil {
			f.onRead()
		}
		f.hub.Flush()
	}
	return u, exp, err
}

func TestFlushDuringWarmDiscardsEntry(t *testing.T) {
	f := newFixture(t)
	// Persistent concurrent flushes must not return or cache pre-flush state.
	f.hub.src = &flushingStore{Store: f.mem, hub: f.hub, remaining: -1}
	if _, err := f.hub.Load(f.token); err == nil {
		t.Fatal("persistent concurrent flush must not return stale principal")
	}
	if _, hit, _ := f.hub.Cached(f.token); hit {
		t.Fatal("a warm that raced a flush must not be cached")
	}
	// A single concurrent logout during warm retries and observes ErrUnauthorized.
	f.hub.src = &flushingStore{
		Store:     f.mem,
		hub:       f.hub,
		remaining: 1,
		onRead:    func() { _ = f.mem.DeleteSession(f.token) },
	}
	if _, err := f.hub.Load(f.token); err != ErrUnauthorized {
		t.Fatalf("concurrent logout during warm must return ErrUnauthorized, got %v", err)
	}
	if _, hit, _ := f.hub.Cached(f.token); hit {
		t.Fatal("revoked session must not be cached")
	}
	// An undisturbed warm succeeds and caches.
	if err := f.mem.CreateSession(f.owner.ID, f.token, time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	f.hub.src = f.mem
	if _, err := f.hub.Load(f.token); err != nil {
		t.Fatal(err)
	}
	if _, hit, _ := f.hub.Cached(f.token); !hit {
		t.Fatal("an undisturbed warm should be cached")
	}
}

func TestNewHubChangesTags(t *testing.T) {
	f := newFixture(t)
	a, err := f.hub.Lookup(f.token)
	if err != nil {
		t.Fatal(err)
	}
	restarted := New()
	Wrap(f.mem, restarted)
	b, err := restarted.Lookup(f.token)
	if err != nil {
		t.Fatal(err)
	}
	if a.ETag == b.ETag || a.Tags.Account == b.Tags.Account || a.Tags.Inbox == b.Tags.Inbox ||
		a.Tags.Calendar == b.Tags.Calendar || a.Tags.Prefs == b.Tags.Prefs {
		t.Fatalf("tags survived a restart: %+v vs %+v", a, b)
	}
}

func TestCachedExpiryAndMaxAge(t *testing.T) {
	f := newFixture(t)
	now := time.Now()
	f.hub.SetClock(func() time.Time { return now })
	if _, err := f.hub.Lookup(f.token); err != nil {
		t.Fatal(err)
	}
	now = now.Add(2 * time.Hour)
	if _, hit, err := f.hub.Cached(f.token); !hit || err != ErrUnauthorized {
		t.Fatalf("expired session: hit=%v err=%v", hit, err)
	}

	if err := f.mem.CreateSession(f.owner.ID, "long", time.Now().Add(48*time.Hour)); err != nil {
		t.Fatal(err)
	}
	now = time.Now()
	if _, err := f.hub.Lookup("long"); err != nil {
		t.Fatal(err)
	}
	now = now.Add(maxCacheAge)
	if _, hit, _ := f.hub.Cached("long"); hit {
		t.Fatal("entries older than maxCacheAge must reload")
	}
}

func TestCapacityClearsCache(t *testing.T) {
	f := newFixture(t)
	f.hub.capacity = 1
	if err := f.mem.CreateSession(f.owner.ID, "second", time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	for _, tok := range []string{f.token, "second"} {
		if _, err := f.hub.Lookup(tok); err != nil {
			t.Fatal(err)
		}
	}
	if len(f.hub.sessions) != 1 {
		t.Fatalf("cache holds %d sessions, capacity 1", len(f.hub.sessions))
	}
	for id := range f.hub.sessions {
		if string(id[:]) == f.token {
			t.Fatal("raw token used as key")
		}
	}
}

func TestDeleteUserForgetsCounters(t *testing.T) {
	f := newFixture(t)
	if _, err := f.s.UpsertEntry(f.owner.ID, "2026-11-01", model.UpsertRequest{}); err != nil {
		t.Fatal(err)
	}
	if f.hub.versions["c:"+f.owner.ID] == 0 {
		t.Fatal("entry write did not bump the calendar counter")
	}
	if err := f.s.DeleteUser(f.owner.ID); err != nil {
		t.Fatal(err)
	}
	if _, ok := f.hub.versions["c:"+f.owner.ID]; ok {
		t.Fatal("deleted user's counters kept")
	}
	if _, err := f.hub.Lookup(f.token); err != ErrUnauthorized {
		t.Fatalf("deleted user's session: %v", err)
	}
}
