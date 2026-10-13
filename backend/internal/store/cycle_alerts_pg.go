package store

import (
	"database/sql"
	"fmt"

	"217/backend/internal/model"
)

// ListPeriodDays filters after opening: the period flag is sealed.
func (s *PGStore) ListPeriodDays(userID, from, to string) ([]string, error) {
	entries, err := s.ListEntriesBetween(userID, from, to)
	if err != nil {
		return nil, fmt.Errorf("listing period days: %w", err)
	}
	out := []string{}
	for _, e := range entries {
		if e.Period {
			out = append(out, e.Date)
		}
	}
	return out, nil
}

func (s *PGStore) GetPartnerAlerts(userID string) (*model.PartnerAlertPreference, error) {
	pref := model.DefaultPartnerAlertPreference()
	err := s.db.QueryRow(
		`SELECT pms_enabled, pms_time, pill_enabled, pill_time, symptom_enabled, symptom_time
		 FROM partner_alert_preferences WHERE user_id = $1`, userID,
	).Scan(&pref.PMSEnabled, &pref.PMSTime, &pref.PillEnabled, &pref.PillTime, &pref.SymptomEnabled, &pref.SymptomTime)
	if err != nil && err != sql.ErrNoRows {
		return nil, fmt.Errorf("getting partner alerts: %w", err)
	}
	return &pref, nil
}

func (s *PGStore) UpsertPartnerAlerts(userID string, pref model.PartnerAlertPreference) (*model.PartnerAlertPreference, error) {
	out := model.PartnerAlertPreference{}
	err := s.db.QueryRow(
		`INSERT INTO partner_alert_preferences (user_id, pms_enabled, pms_time, pill_enabled, pill_time, symptom_enabled, symptom_time)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 ON CONFLICT (user_id) DO UPDATE SET
		   pms_enabled = EXCLUDED.pms_enabled,
		   pms_time = EXCLUDED.pms_time,
		   pill_enabled = EXCLUDED.pill_enabled,
		   pill_time = EXCLUDED.pill_time,
		   symptom_enabled = EXCLUDED.symptom_enabled,
		   symptom_time = EXCLUDED.symptom_time,
		   updated_at = NOW()
		 RETURNING pms_enabled, pms_time, pill_enabled, pill_time, symptom_enabled, symptom_time`,
		userID, pref.PMSEnabled, pref.PMSTime, pref.PillEnabled, pref.PillTime, pref.SymptomEnabled, pref.SymptomTime,
	).Scan(&out.PMSEnabled, &out.PMSTime, &out.PillEnabled, &out.PillTime, &out.SymptomEnabled, &out.SymptomTime)
	if err != nil {
		return nil, fmt.Errorf("saving partner alerts: %w", err)
	}
	return &out, nil
}
