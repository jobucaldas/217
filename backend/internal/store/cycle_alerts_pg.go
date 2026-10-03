package store

import (
	"database/sql"
	"fmt"
	"time"

	"217/backend/internal/model"
)

func (s *PGStore) ListPeriodDays(userID, from, to string) ([]string, error) {
	rows, err := s.db.Query(
		`SELECT date FROM entries
		 WHERE user_id = $1 AND period AND date >= $2 AND date <= $3
		 ORDER BY date ASC`, userID, from, to,
	)
	if err != nil {
		return nil, fmt.Errorf("listing period days: %w", err)
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return nil, fmt.Errorf("scanning period day: %w", err)
		}
		out = append(out, formatDate(d))
	}
	return out, rows.Err()
}

func (s *PGStore) GetPartnerAlerts(userID string) (*model.PartnerAlertPreference, error) {
	pref := model.DefaultPartnerAlertPreference()
	err := s.db.QueryRow(
		`SELECT pms_enabled, pms_time, pill_enabled, pill_time
		 FROM partner_alert_preferences WHERE user_id = $1`, userID,
	).Scan(&pref.PMSEnabled, &pref.PMSTime, &pref.PillEnabled, &pref.PillTime)
	if err != nil && err != sql.ErrNoRows {
		return nil, fmt.Errorf("getting partner alerts: %w", err)
	}
	return &pref, nil
}

func (s *PGStore) UpsertPartnerAlerts(userID string, pref model.PartnerAlertPreference) (*model.PartnerAlertPreference, error) {
	out := model.PartnerAlertPreference{}
	err := s.db.QueryRow(
		`INSERT INTO partner_alert_preferences (user_id, pms_enabled, pms_time, pill_enabled, pill_time)
		 VALUES ($1, $2, $3, $4, $5)
		 ON CONFLICT (user_id) DO UPDATE SET
		   pms_enabled = EXCLUDED.pms_enabled,
		   pms_time = EXCLUDED.pms_time,
		   pill_enabled = EXCLUDED.pill_enabled,
		   pill_time = EXCLUDED.pill_time,
		   updated_at = NOW()
		 RETURNING pms_enabled, pms_time, pill_enabled, pill_time`,
		userID, pref.PMSEnabled, pref.PMSTime, pref.PillEnabled, pref.PillTime,
	).Scan(&out.PMSEnabled, &out.PMSTime, &out.PillEnabled, &out.PillTime)
	if err != nil {
		return nil, fmt.Errorf("saving partner alerts: %w", err)
	}
	return &out, nil
}
