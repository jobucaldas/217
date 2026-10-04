package store

import (
	"crypto/rand"
	"database/sql"
	"net/url"
	"os"
	"strings"
	"testing"

	"217/backend/db"
	"217/backend/internal/fieldcrypt"
	"217/backend/internal/model"
)

// pgTestDSN points at a throwaway schema in TEST_DATABASE_URL, or skips.
func pgTestDSN(t *testing.T) string {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set TEST_DATABASE_URL to a disposable PostgreSQL database")
	}
	admin, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	schema := "test_" + generateID()
	if _, err := admin.Exec(`CREATE SCHEMA "` + schema + `"`); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if _, err := admin.Exec(`DROP SCHEMA "` + schema + `" CASCADE`); err != nil {
			t.Error(err)
		}
		admin.Close()
	})
	u, err := url.Parse(dsn)
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	q.Set("search_path", schema)
	u.RawQuery = q.Encode()
	return u.String()
}

func testKeyring(t *testing.T) *fieldcrypt.Keyring {
	t.Helper()
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	kr, err := fieldcrypt.New(key)
	if err != nil {
		t.Fatal(err)
	}
	return kr
}

// openPG connects to dsn with kr, closing the store when the test ends.
func openPG(t *testing.T, dsn string, kr *fieldcrypt.Keyring) *PGStore {
	t.Helper()
	s, err := NewPGStore(dsn, kr)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

// pgTestStore returns a migrated PGStore in a throwaway schema, or skips.
func pgTestStore(t *testing.T) *PGStore {
	t.Helper()
	kr := testKeyring(t)
	s := openPG(t, pgTestDSN(t), kr)
	if err := db.Migrate(s.db, MigrationSteps(kr)); err != nil {
		t.Fatal(err)
	}
	if err := s.Prepare(); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestRolesCycleAlertsStoreContract(t *testing.T) {
	t.Run("memory", func(t *testing.T) { testRolesCycleAlerts(t, NewMemoryStore()) })
	t.Run("postgres", func(t *testing.T) { testRolesCycleAlerts(t, pgTestStore(t)) })
}

func testRolesCycleAlerts(t *testing.T, s Store) {
	owner, err := s.LinkWorkOSIdentity("user_owner", "girl@example.com", "Girl", true)
	if err != nil {
		t.Fatal(err)
	}
	if owner.Role != "" {
		t.Fatalf("new users start without a role, got %q", owner.Role)
	}
	if _, err := s.CalendarSubjectID(owner.ID); err == nil {
		t.Fatal("expected no calendar before choosing a role")
	}
	if _, err := s.SetRole(owner.ID, "admin"); err == nil {
		t.Fatal("expected invalid role error")
	}
	if u, err := s.SetRole(owner.ID, model.RoleOwner); err != nil || u.Role != model.RoleOwner {
		t.Fatalf("set owner: %+v %v", u, err)
	}

	for _, d := range []string{"2026-09-01", "2026-09-02", "2026-09-29"} {
		if _, err := s.UpsertEntry(owner.ID, d, model.UpsertRequest{Period: true}); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := s.UpsertEntry(owner.ID, "2026-09-03", model.UpsertRequest{Taken: model.BoolPtr(true)}); err != nil {
		t.Fatal(err)
	}
	e, err := s.GetEntry(owner.ID, "2026-09-29")
	if err != nil || !e.Period || e.Taken != nil {
		t.Fatalf("period entry: %+v %v", e, err)
	}
	days, err := s.ListPeriodDays(owner.ID, "2026-09-02", "2026-12-31")
	if err != nil || strings.Join(days, ",") != "2026-09-02,2026-09-29" {
		t.Fatalf("period days: %v %v", days, err)
	}

	partner, err := s.LinkWorkOSIdentity("user_partner", "bf@example.com", "Bf", true)
	if err != nil {
		t.Fatal(err)
	}
	share, err := s.EnableShare(owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.AcceptShare(partner.ID, share.InviteCode); err != nil {
		t.Fatal(err)
	}
	if subject, err := s.CalendarSubjectID(partner.ID); err != nil || subject != owner.ID {
		t.Fatalf("partner subject %q %v", subject, err)
	}
	if _, err := s.SetRole(owner.ID, model.RolePartner); err == nil {
		t.Fatal("owner role must be locked while sharing")
	}
	if _, err := s.SetRole(partner.ID, model.RoleOwner); err == nil {
		t.Fatal("partner role must be locked while linked")
	}

	pref, err := s.GetPartnerAlerts(partner.ID)
	if err != nil || pref.PMSTime != model.DefaultPMSTime || pref.PillTime != model.DefaultPillTime || pref.PMSEnabled {
		t.Fatalf("default alerts: %+v %v", pref, err)
	}
	saved, err := s.UpsertPartnerAlerts(partner.ID, model.PartnerAlertPreference{PMSEnabled: true, PMSTime: "07:45", PillTime: "22:00"})
	if err != nil || !saved.PMSEnabled || saved.PMSTime != "07:45" || saved.PillEnabled {
		t.Fatalf("saved alerts: %+v %v", saved, err)
	}
}

func TestMigrationLetsUnusedOwnersPickRole(t *testing.T) {
	kr := testKeyring(t)
	s := openPG(t, pgTestDSN(t), kr)
	// Seed the schema as it was before 016, then upgrade.
	if err := db.MigrateBefore(s.db, nil, "016"); err != nil {
		t.Fatal(err)
	}
	mustExec := func(q string, args ...any) {
		t.Helper()
		if _, err := s.db.Exec(q, args...); err != nil {
			t.Fatal(err)
		}
	}
	var active, idle, partner string
	for _, row := range []struct {
		email, role string
		id          *string
	}{{"active@example.com", "owner", &active}, {"idle@example.com", "owner", &idle}, {"bf@example.com", "partner", &partner}} {
		if err := s.db.QueryRow(`INSERT INTO users (email, name, api_key, password_hash, role)
			VALUES ($1, $1, $1, '', $2) RETURNING id`, row.email, row.role).Scan(row.id); err != nil {
			t.Fatal(err)
		}
	}
	mustExec(`INSERT INTO entries (user_id, date, taken) VALUES ($1, '2026-09-01', true)`, active)
	if err := db.Migrate(s.db, MigrationSteps(kr)); err != nil {
		t.Fatal(err)
	}
	for id, want := range map[string]string{active: "owner", idle: "", partner: "partner"} {
		u, err := s.GetUserByID(id)
		if err != nil || u.Role != want {
			t.Fatalf("user %s role %q want %q (%v)", id, u.Role, want, err)
		}
	}
}
