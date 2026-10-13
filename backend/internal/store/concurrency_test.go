package store

import (
	"database/sql"
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

func TestConcurrentPushSaveCorrectionFailureIsAtomic(t *testing.T) {
	s := pgTestStore(t)
	u, err := s.LinkWorkOSIdentity("owner", "owner@example.com", "Owner", true)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpsertReminderPreference(u.ID, model.ReminderPreference{Enabled: true, Time: "08:00", Timezone: "UTC"}); err != nil {
		t.Fatal(err)
	}
	// Block both first inserts until both requests have selected their own IDs.
	// Fail the corrective UPDATE, but allow the ON CONFLICT update. The winner's
	// ciphertext must remain readable even when the losing save cannot finish.
	if _, err := s.db.Exec(`CREATE FUNCTION gate_push_insert() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN
  PERFORM pg_advisory_xact_lock(64001);
  RETURN NEW;
 END $$;
 CREATE TRIGGER gate_push BEFORE INSERT ON push_subscriptions FOR EACH ROW EXECUTE FUNCTION gate_push_insert();
 CREATE FUNCTION fail_push_correction() RETURNS trigger LANGUAGE plpgsql AS $$
 BEGIN
  IF NEW.updated_at = OLD.updated_at THEN RAISE EXCEPTION 'correction failed'; END IF;
  RETURN NEW;
 END $$;
 CREATE TRIGGER fail_correction BEFORE UPDATE ON push_subscriptions FOR EACH ROW EXECUTE FUNCTION fail_push_correction();`); err != nil {
		t.Fatal(err)
	}
	gate, err := s.db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer gate.Rollback()
	if _, err := gate.Exec(`SELECT pg_advisory_xact_lock(64001)`); err != nil {
		t.Fatal(err)
	}
	results := make(chan error, 2)
	for i := 0; i < 2; i++ {
		go func() {
			_, err := s.SavePushSubscription(u.ID, model.PushSubscriptionRequest{Endpoint: "https://push.example/concurrent"})
			results <- err
		}()
	}
	waitForDBLocks(t, s.db, `SELECT count(*) FROM pg_stat_activity WHERE wait_event = 'advisory' AND query LIKE 'INSERT INTO push_subscriptions%'`, 2)
	if err := gate.Commit(); err != nil {
		t.Fatal(err)
	}
	failures := 0
	for i := 0; i < 2; i++ {
		select {
		case err := <-results:
			if err != nil {
				failures++
			}
		case <-time.After(10 * time.Second):
			t.Fatal("push save did not finish")
		}
	}
	if failures != 1 {
		t.Fatalf("want one failed correction, got %d failures", failures)
	}
	targets, err := s.ListReminderTargets()
	if err != nil || len(targets) != 1 || targets[0].Endpoint != "https://push.example/concurrent" {
		t.Fatalf("winner's subscription was corrupted: %+v, %v", targets, err)
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
