package store

import (
	"testing"

	"217/backend/internal/model"
)

func TestPartnerAlertPillRepeatRoundTrip(t *testing.T) {
	forEachStore(t, func(t *testing.T, name string, s Store) {
		partner, err := s.LinkWorkOSIdentity("repeat-"+name, "repeat-"+name+"@example.com", "Bf", true)
		if err != nil {
			t.Fatal(err)
		}
		def, err := s.GetPartnerAlerts(partner.ID)
		if err != nil || def.PillRepeatMinutes != model.PillRepeatOff {
			t.Fatalf("default repeat: %+v %v", def, err)
		}
		saved, err := s.UpsertPartnerAlerts(partner.ID, model.PartnerAlertPreference{PillEnabled: true, PillTime: "21:00", PillRepeatMinutes: 45})
		if err != nil || saved.PillRepeatMinutes != 45 {
			t.Fatalf("saved repeat: %+v %v", saved, err)
		}
		got, err := s.GetPartnerAlerts(partner.ID)
		if err != nil || got.PillRepeatMinutes != 45 || !got.PillEnabled {
			t.Fatalf("read repeat: %+v %v", got, err)
		}
		if _, err := s.UpsertPartnerAlerts(partner.ID, model.PartnerAlertPreference{PillEnabled: true, PillTime: "21:00"}); err != nil {
			t.Fatal(err)
		}
		got, err = s.GetPartnerAlerts(partner.ID)
		if err != nil || got.PillRepeatMinutes != model.PillRepeatOff {
			t.Fatalf("repeat cleared: %+v %v", got, err)
		}
	})
}

func TestPillRepeatMigrationDefaultsOff(t *testing.T) {
	s := pgTestStore(t)
	partner, err := s.LinkWorkOSIdentity("repeat-migration", "repeat-migration@example.com", "Bf", true)
	if err != nil {
		t.Fatal(err)
	}
	// A row written before migration 022 has no repeat value at all.
	if _, err := s.db.Exec(`INSERT INTO partner_alert_preferences (user_id, pill_enabled) VALUES ($1, true)`, partner.ID); err != nil {
		t.Fatal(err)
	}
	got, err := s.GetPartnerAlerts(partner.ID)
	if err != nil || got.PillRepeatMinutes != model.PillRepeatOff || !got.PillEnabled {
		t.Fatalf("migrated row: %+v %v", got, err)
	}
	if _, err := s.db.Exec(`UPDATE partner_alert_preferences SET pill_repeat_minutes = 121 WHERE user_id = $1`, partner.ID); err == nil {
		t.Fatal("out-of-range repeat stored")
	}
}
