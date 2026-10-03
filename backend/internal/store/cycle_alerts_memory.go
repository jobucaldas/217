package store

import (
	"sort"
	"strings"

	"217/backend/internal/model"
)

func (s *MemoryStore) ListPeriodDays(userID, from, to string) ([]string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	prefix := userID + ":"
	out := []string{}
	for k, e := range s.entries {
		if !strings.HasPrefix(k, prefix) || !e.Period {
			continue
		}
		if e.Date >= from && e.Date <= to {
			out = append(out, e.Date)
		}
	}
	sort.Strings(out)
	return out, nil
}

func (s *MemoryStore) GetPartnerAlerts(userID string) (*model.PartnerAlertPreference, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	pref, ok := s.partnerAlerts[userID]
	if !ok {
		pref = model.DefaultPartnerAlertPreference()
	}
	return &pref, nil
}

func (s *MemoryStore) UpsertPartnerAlerts(userID string, pref model.PartnerAlertPreference) (*model.PartnerAlertPreference, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.partnerAlerts[userID] = pref
	out := pref
	return &out, nil
}
