package store

import (
	"crypto/rand"
	"database/sql"
	"strings"
	"testing"
	"time"

	"217/backend/db"
	"217/backend/internal/fieldcrypt"
	"217/backend/internal/model"
)

// dumpSchema returns every value in the current schema as text, the way a
// leaked dump or volume would expose it.
func dumpSchema(t *testing.T, conn *sql.DB) string {
	t.Helper()
	rows, err := conn.Query(`SELECT table_name FROM information_schema.tables
		WHERE table_schema = current_schema() AND table_type = 'BASE TABLE'`)
	if err != nil {
		t.Fatal(err)
	}
	var tables []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatal(err)
		}
		tables = append(tables, name)
	}
	rows.Close()
	var out strings.Builder
	for _, table := range tables {
		var text sql.NullString
		if err := conn.QueryRow(`SELECT string_agg(t::text, E'\n') FROM "` + table + `" t`).Scan(&text); err != nil {
			t.Fatal(err)
		}
		out.WriteString(text.String)
	}
	return out.String()
}

func TestSealExistingRowsDropsPlaintext(t *testing.T) {
	kr := testKeyring(t)
	s := openPG(t, pgTestDSN(t), kr)
	if err := db.MigrateBefore(s.db, nil, "017"); err != nil {
		t.Fatal(err)
	}
	mustExec := func(q string, args ...any) {
		t.Helper()
		if _, err := s.db.Exec(q, args...); err != nil {
			t.Fatal(err)
		}
	}
	var owner, partner string
	if err := s.db.QueryRow(`INSERT INTO users (email, name, api_key, role) VALUES ('Owner@Example.com', 'Ana Secret', 'k1', 'owner') RETURNING id`).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	if err := s.db.QueryRow(`INSERT INTO users (email, name, api_key, role) VALUES ('bf@example.com', 'Bo Secret', 'k2', 'partner') RETURNING id`).Scan(&partner); err != nil {
		t.Fatal(err)
	}
	mustExec(`INSERT INTO workos_identities (subject, user_id, email_normalized) VALUES ('user_owner', $1, 'owner@example.com')`, owner)
	mustExec(`INSERT INTO entries (user_id, date, taken, notes, heart, period) VALUES ($1, '2026-09-01', true, 'cramps note', true, true)`, owner)
	mustExec(`INSERT INTO entries (user_id, date, taken, notes) VALUES ($1, '2026-09-02', NULL, '')`, owner)
	mustExec(`INSERT INTO calendar_shares (owner_id, partner_id, invite_code, status) VALUES ($1, $2, 'INVITEXY', 'active')`, owner, partner)
	mustExec(`INSERT INTO partner_notes (owner_id, partner_id, body) VALUES ($1, $2, 'love note body')`, owner, partner)
	mustExec(`INSERT INTO push_subscriptions (user_id, endpoint, p256dh, auth) VALUES ($1, 'https://push.example/secret-endpoint', 'p256-key', 'auth-key')`, owner)
	mustExec(`INSERT INTO sessions (id, user_id, expires_at, user_agent, ip_address) VALUES ('h', $1, NOW() + INTERVAL '1 hour', 'Firefox', '203.0.113.9')`, owner)

	if err := db.Migrate(s.db, MigrationSteps(kr)); err != nil {
		t.Fatal(err)
	}
	if err := s.Prepare(); err != nil {
		t.Fatal(err)
	}

	dump := dumpSchema(t, s.db)
	for _, secret := range []string{"Owner@Example.com", "owner@example.com", "Ana Secret", "Bo Secret", "cramps note", "INVITEXY", "love note body", "secret-endpoint", "p256-key", "auth-key", "Firefox", "203.0.113.9"} {
		if strings.Contains(dump, secret) {
			t.Errorf("plaintext %q still stored", secret)
		}
	}

	u, err := s.LinkWorkOSIdentity("user_owner", "owner@example.com", "", true)
	if err != nil || u.ID != owner || u.Email != "Owner@Example.com" || u.Name != "Ana Secret" {
		t.Fatalf("owner after sealing: %+v %v", u, err)
	}
	e, err := s.GetEntry(owner, "2026-09-01")
	if err != nil || !model.TakenTrue(e.Taken) || e.Notes != "cramps note" || !e.Heart || !e.Period {
		t.Fatalf("entry after sealing: %+v %v", e, err)
	}
	if e, err := s.GetEntry(owner, "2026-09-02"); err != nil || e.Taken != nil {
		t.Fatalf("open entry after sealing: %+v %v", e, err)
	}
	if days, err := s.ListPeriodDays(owner, "2026-09-01", "2026-09-30"); err != nil || strings.Join(days, ",") != "2026-09-01" {
		t.Fatalf("period days: %v %v", days, err)
	}
	state, err := s.GetShareState(owner)
	if err != nil || state.InviteCode != "INVITEXY" || state.PartnerName != "Bo Secret" {
		t.Fatalf("share after sealing: %+v %v", state, err)
	}
	notes, err := s.ListInboxNotes(owner)
	if err != nil || len(notes) != 1 || notes[0].Body != "love note body" || notes[0].FromEmail != "bf@example.com" {
		t.Fatalf("notes after sealing: %+v %v", notes, err)
	}
	targets, err := s.UpsertReminderPreference(owner, model.ReminderPreference{Enabled: true, Time: "08:00", Timezone: "UTC"})
	if err != nil || targets.SubscriptionCount != 1 {
		t.Fatalf("subscription after sealing: %+v %v", targets, err)
	}
	list, err := s.ListReminderTargets()
	if err != nil || len(list) != 1 || list[0].Endpoint != "https://push.example/secret-endpoint" || list[0].Auth != "auth-key" {
		t.Fatalf("reminder targets after sealing: %+v %v", list, err)
	}
}

func TestSealedValuesStayOnTheirRow(t *testing.T) {
	s := pgTestStore(t)
	a, _ := s.LinkWorkOSIdentity("a", "a@example.com", "A", true)
	b, _ := s.LinkWorkOSIdentity("b", "b@example.com", "B", true)
	if _, err := s.UpsertEntry(a.ID, "2026-09-01", model.UpsertRequest{Notes: "a's note"}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpsertEntry(b.ID, "2026-09-01", model.UpsertRequest{Notes: "b's note"}); err != nil {
		t.Fatal(err)
	}
	// Someone with database write access copies a's sealed note onto b's row.
	if _, err := s.db.Exec(`UPDATE entries SET sealed = (SELECT sealed FROM entries WHERE user_id = $1) WHERE user_id = $2`, a.ID, b.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.GetEntry(b.ID, "2026-09-01"); err == nil {
		t.Fatal("a sealed value moved to another user's row still opened")
	}
}

func TestKeyRotationReseals(t *testing.T) {
	dsn := pgTestDSN(t)
	oldKey, newKey := make([]byte, 32), make([]byte, 32)
	_, _ = rand.Read(oldKey)
	_, _ = rand.Read(newKey)
	oldKR, _ := fieldcrypt.New(oldKey)
	s := openPG(t, dsn, oldKR)
	if err := db.Migrate(s.db, MigrationSteps(oldKR)); err != nil {
		t.Fatal(err)
	}
	owner, _ := s.LinkWorkOSIdentity("owner", "owner@example.com", "Owner", true)
	if _, err := s.SetRole(owner.ID, model.RoleOwner); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpsertEntry(owner.ID, "2026-09-01", model.UpsertRequest{Notes: "kept"}); err != nil {
		t.Fatal(err)
	}
	share, err := s.EnableShare(owner.ID)
	if err != nil {
		t.Fatal(err)
	}

	newOnly, _ := fieldcrypt.New(newKey)
	if err := openPG(t, dsn, newOnly).Prepare(); err == nil {
		t.Fatal("a key that cannot open the data was accepted")
	}

	rotating, _ := fieldcrypt.New(newKey, oldKey)
	r := openPG(t, dsn, rotating)
	if err := r.Prepare(); err != nil {
		t.Fatal(err)
	}
	// Everything now opens with the new key alone, lookups included.
	n := openPG(t, dsn, newOnly)
	if err := n.Prepare(); err != nil {
		t.Fatalf("after reseal: %v", err)
	}
	if e, err := n.GetEntry(owner.ID, "2026-09-01"); err != nil || e.Notes != "kept" {
		t.Fatalf("entry after rotation: %+v %v", e, err)
	}
	if u, err := n.LinkWorkOSIdentity("owner", "owner@example.com", "", true); err != nil || u.Email != "owner@example.com" {
		t.Fatalf("user after rotation: %+v %v", u, err)
	}
	partner, _ := n.LinkWorkOSIdentity("partner", "bf@example.com", "Bf", true)
	if _, err := n.AcceptShare(partner.ID, share.InviteCode); err != nil {
		t.Fatalf("invite lookup after rotation: %v", err)
	}
}

func TestStatsFromSealedEntries(t *testing.T) {
	s := pgTestStore(t)
	u, _ := s.LinkWorkOSIdentity("u", "u@example.com", "U", true)
	today := time.Now().UTC()
	for i := 0; i < 3 && today.AddDate(0, 0, -i).Month() == today.Month(); i++ {
		if _, err := s.UpsertEntry(u.ID, formatDate(today.AddDate(0, 0, -i)), model.UpsertRequest{Taken: model.BoolPtr(true)}); err != nil {
			t.Fatal(err)
		}
	}
	stats, err := s.GetStats(u.ID, today.Year(), int(today.Month()))
	if err != nil {
		t.Fatal(err)
	}
	want := min(3, today.Day())
	if stats.TakenDays != want || stats.Streak != want || stats.MissedDays != stats.TotalDays-want {
		t.Fatalf("stats = %+v, want %d taken", stats, want)
	}
}
