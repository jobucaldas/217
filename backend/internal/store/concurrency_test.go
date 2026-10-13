package store

import (
	"database/sql"
	"fmt"
	"strings"
	"testing"
	"time"

	"217/backend/db"
	"217/backend/internal/fieldcrypt"
	"217/backend/internal/model"
)

// Wait for a database lock instead of relying on scheduler timing.
func waitForDBLocks(t *testing.T, db *sql.DB, query string, want int) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		var count int
		if err := db.QueryRow(query).Scan(&count); err != nil {
			t.Fatal(err)
		}
		if count >= want {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("timed out waiting for database locks")
}

// holdUser locks the user's row, as a push save does, until release is called.
func holdUser(t *testing.T, db *sql.DB, userID string) (release func()) {
	t.Helper()
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	// Never left open on failure: it would block the schema cleanup.
	t.Cleanup(func() { _ = tx.Rollback() })
	if _, err := tx.Exec(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, userID); err != nil {
		t.Fatal(err)
	}
	return func() {
		if err := tx.Commit(); err != nil {
			t.Fatal(err)
		}
	}
}

// startPushSaves runs one save per endpoint at once, all queued behind the
// user's row lock, and returns their errors once released.
func startPushSaves(t *testing.T, s *PGStore, userID string, endpoints ...string) []error {
	t.Helper()
	release := holdUser(t, s.db, userID)
	results := make(chan error, len(endpoints))
	for _, endpoint := range endpoints {
		go func() {
			_, err := s.SavePushSubscription(userID, model.PushSubscriptionRequest{Endpoint: endpoint})
			results <- err
		}()
	}
	waitForDBLocks(t, s.db, `SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND query LIKE 'SELECT id FROM users%'`, len(endpoints))
	release()
	var errs []error
	for range endpoints {
		select {
		case err := <-results:
			errs = append(errs, err)
		case <-time.After(10 * time.Second):
			t.Fatal("push save did not finish")
		}
	}
	return errs
}

// Saves of one user run one at a time, so a concurrent first save of the
// same endpoint finds the row and its seal stays bound to that row's id.
func TestConcurrentPushSavesOfOneEndpointSerialize(t *testing.T) {
	s := pgTestStore(t)
	u, err := s.LinkWorkOSIdentity("owner", "owner@example.com", "Owner", true)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpsertReminderPreference(u.ID, model.ReminderPreference{Enabled: true, Time: "08:00", Timezone: "UTC"}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.RecordConsent(u.ID, model.ConsentVersion); err != nil {
		t.Fatal(err)
	}
	for _, err := range startPushSaves(t, s, u.ID, "https://push.example/same", "https://push.example/same") {
		if err != nil {
			t.Fatalf("concurrent save of one endpoint failed: %v", err)
		}
	}
	targets, err := s.ListReminderTargets()
	if err != nil || len(targets) != 1 || targets[0].Endpoint != "https://push.example/same" {
		t.Fatalf("subscription after concurrent saves: %+v, %v", targets, err)
	}
}

// Concurrent saves of new endpoints cannot push a user past the limit.
func TestConcurrentPushSavesRespectTheLimit(t *testing.T) {
	s := pgTestStore(t)
	u, err := s.LinkWorkOSIdentity("owner", "owner@example.com", "Owner", true)
	if err != nil {
		t.Fatal(err)
	}
	for i := 1; i < model.MaxPushSubscriptions; i++ {
		if _, err := s.SavePushSubscription(u.ID, model.PushSubscriptionRequest{Endpoint: fmt.Sprintf("https://push.example/%d", i)}); err != nil {
			t.Fatal(err)
		}
	}
	saved := 0
	for _, err := range startPushSaves(t, s, u.ID, "https://push.example/a", "https://push.example/b", "https://push.example/c") {
		if err == nil {
			saved++
		} else if !strings.Contains(err.Error(), "limit reached") {
			t.Fatalf("unexpected error: %v", err)
		}
	}
	count, err := s.CountPushSubscriptions(u.ID)
	if err != nil || saved != 1 || count != model.MaxPushSubscriptions {
		t.Fatalf("saved %d, stored %d (%v), want 1 and %d", saved, count, err, model.MaxPushSubscriptions)
	}
}

func TestRotationPreservesConcurrentEntryEdit(t *testing.T) {
	oldKey, newKey := make([]byte, 32), make([]byte, 32)
	oldKey[0], newKey[0] = 1, 2
	oldKR, err := fieldcrypt.New(oldKey)
	if err != nil {
		t.Fatal(err)
	}
	s := openPG(t, pgTestDSN(t), oldKR)
	if err := db.Migrate(s.db, MigrationSteps(oldKR)); err != nil {
		t.Fatal(err)
	}
	u, err := s.LinkWorkOSIdentity("owner", "owner@example.com", "Owner", true)
	if err != nil {
		t.Fatal(err)
	}
	const date = "2026-09-01"
	if _, err := s.UpsertEntry(u.ID, date, model.UpsertRequest{Notes: "before"}); err != nil {
		t.Fatal(err)
	}
	rotating, err := fieldcrypt.New(newKey, oldKey)
	if err != nil {
		t.Fatal(err)
	}
	r := &PGStore{db: s.db, kr: rotating}
	// Hold an uncommitted edit while rotation reaches this row. Rotation must
	// wait and read the committed edit rather than rewrite the old snapshot.
	writer, err := s.db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer writer.Rollback()
	if _, err := writer.Exec(`UPDATE entries SET sealed=$1 WHERE user_id=$2`, sealJSON(oldKR, entryPayload{Notes: "acknowledged edit"}, entryCtx(u.ID, date)), u.ID); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- r.reseal() }()
	waitForDBLocks(t, s.db, `SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' AND (query LIKE 'SELECT id, user_id, to_char%' OR query LIKE 'UPDATE entries SET sealed%')`, 1)
	if err := writer.Commit(); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("rotation did not finish")
	}
	entry, err := r.GetEntry(u.ID, date)
	if err != nil || entry.Notes != "acknowledged edit" {
		t.Fatalf("concurrent edit lost: %+v, %v", entry, err)
	}
}
