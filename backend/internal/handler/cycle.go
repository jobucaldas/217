package handler

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"217/backend/internal/cycle"
	"217/backend/internal/model"
	"217/backend/internal/store"
)

// writeCalendarSubjectError explains why the caller has no calendar to read.
func writeCalendarSubjectError(w http.ResponseWriter, err error) {
	if errors.Is(err, store.ErrRoleNotChosen) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "role not chosen"})
	} else if errors.Is(err, store.ErrShareInactive) || errors.Is(err, store.ErrUserNotFound) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "share inactive"})
	} else {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "service unavailable"})
	}
}

// SetRole lets a user pick owner (logs the pill) or partner (follows a calendar).
func (h *Handler) SetRole(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Role string `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	user, err := h.store.SetRole(getUserID(r), body.Role)
	if err != nil {
		msg := err.Error()
		switch {
		case strings.Contains(msg, "must be"):
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": msg})
		case strings.Contains(msg, "locked"):
			writeJSON(w, http.StatusConflict, map[string]string{"error": msg})
		default:
			log.Printf("set role: %v", err)
			http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		}
		return
	}
	h.notifyReminders()
	h.writeSession(w, user)
}

// GetCycle returns logged period starts and the next predicted periods/PMS
// windows for the calendar the caller can see. ?today=YYYY-MM-DD is the
// client's local date (defaults to UTC today).
func (h *Handler) GetCycle(w http.ResponseWriter, r *http.Request) {
	subjectID, err := h.calendarSubject(getUserID(r))
	if err != nil {
		writeCalendarSubjectError(w, err)
		return
	}
	if err := h.requireSubjectConsent(w, getUserID(r), subjectID); err != nil {
		return
	}
	owner, err := h.store.GetUserByID(subjectID)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	today := time.Now().UTC()
	if raw := r.URL.Query().Get("today"); raw != "" {
		parsed, err := time.Parse("2006-01-02", raw)
		if err != nil {
			http.Error(w, `{"error":"invalid today, use YYYY-MM-DD"}`, http.StatusBadRequest)
			return
		}
		// Client clocks can drift a day either side of UTC, not more.
		if d := parsed.Sub(today); d > 48*time.Hour || d < -48*time.Hour {
			http.Error(w, `{"error":"today is out of range"}`, http.StatusBadRequest)
			return
		}
		today = parsed
	}
	from := today.AddDate(0, 0, -cycle.HistoryDays).Format("2006-01-02")
	days, err := h.store.ListPeriodDays(subjectID, from, today.Format("2006-01-02"))
	if err != nil {
		log.Printf("list period days: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	info := cycle.Predict(days, today)
	note := ""
	switch owner.Stage {
	case model.StageMenopause:
		note = "pms_suppressed_menopause"
		for i := range info.Predictions {
			info.Predictions[i].PMSStart = ""
			info.Predictions[i].PMSEnd = ""
		}
	case model.StageNoCycles:
		note = "no_cycles"
		info.Predictions = []model.CycleWindow{}
	case "perimenopause":
		note = "pms_counted_perimenopause"
	}
	out := map[string]any{"subject_id": subjectID, "stage": owner.Stage, "period_starts": info.PeriodStarts, "cycle_length": info.CycleLength, "period_length": info.PeriodLength, "estimated": info.Estimated, "predictions": info.Predictions, "note": note}
	// The stage suggestion is for the owner only, never her partner.
	if subjectID == getUserID(r) && owner.EffectiveRole() == model.RoleOwner {
		suggested, err := h.suggestStage(owner, days, today)
		if err != nil {
			log.Printf("suggest stage: %v", err)
			http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
			return
		}
		if suggested != "" {
			out["suggested_stage"] = suggested
		}
	}
	writeJSON(w, http.StatusOK, out)
}

// suggestStage runs cycle.SuggestStage on the owner's data. recent are the
// period days of the last cycle.HistoryDays; older ones are only read when
// that window holds none, since only the latest period day matters.
func (h *Handler) suggestStage(owner *model.User, recent []string, today time.Time) (string, error) {
	days := recent
	if len(days) == 0 {
		before := today.AddDate(0, 0, -cycle.HistoryDays-1).Format("2006-01-02")
		older, err := h.store.ListPeriodDays(owner.ID, "0001-01-01", before)
		if err != nil {
			return "", err
		}
		days = older
	}
	return cycle.SuggestStage(owner.Stage, owner.BirthDate, days, today), nil
}

// UpdateProfile sets the caller's display name (both roles) and birth month
// (owners only). Omitted fields are kept; an empty value clears the field,
// so an empty display name falls back to the sign-in profile name.
func (h *Handler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DisplayName *string `json:"display_name"`
		BirthDate   *string `json:"birth_date"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	userID := getUserID(r)
	user, err := h.store.GetUserByID(userID)
	if err != nil {
		if errors.Is(err, store.ErrUserNotFound) {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		} else {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "service unavailable"})
		}
		return
	}
	if body.DisplayName != nil {
		name := strings.TrimSpace(*body.DisplayName)
		if !validDisplayName(name) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "display_name must be at most 60 characters, without control characters"})
			return
		}
		body.DisplayName = &name
	}
	if body.BirthDate != nil {
		birth := strings.TrimSpace(*body.BirthDate)
		if birth != "" && user.EffectiveRole() != model.RoleOwner {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "only owners may set birth_date"})
			return
		}
		if birth != "" && !validBirthMonth(birth, time.Now().UTC()) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "birth_date must be a past month, YYYY-MM"})
			return
		}
		body.BirthDate = &birth
	}
	updated, err := h.store.SetProfile(userID, body.DisplayName, body.BirthDate)
	if err != nil {
		log.Printf("set profile: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	h.writeSession(w, updated)
}

func validDisplayName(name string) bool {
	if !utf8.ValidString(name) || utf8.RuneCountInString(name) > model.MaxDisplayNameRunes {
		return false
	}
	for _, r := range name {
		if unicode.IsControl(r) {
			return false
		}
	}
	return true
}

// validBirthMonth accepts YYYY-MM from 1900 up to the current month (a day
// of slack for clients ahead of UTC).
func validBirthMonth(v string, now time.Time) bool {
	t, err := time.Parse(cycle.BirthMonthLayout, v)
	if err != nil || len(v) != 7 || t.Year() < 1900 {
		return false
	}
	return !t.After(now.Add(24 * time.Hour))
}

func (h *Handler) SetStage(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Stage string `json:"stage"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if !model.ValidStage(body.Stage) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid stage"})
		return
	}
	user, err := h.store.GetUserByID(getUserID(r))
	if err != nil && !errors.Is(err, store.ErrUserNotFound) {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "service unavailable"})
		return
	}
	if err != nil || user.EffectiveRole() != model.RoleOwner {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "only owners may set stage"})
		return
	}
	updated, err := h.store.SetStage(getUserID(r), body.Stage)
	if err != nil {
		log.Printf("set stage: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	h.writeSession(w, updated)
}

func (h *Handler) isPartner(w http.ResponseWriter, userID string) bool {
	user, err := h.store.GetUserByID(userID)
	if err != nil && !errors.Is(err, store.ErrUserNotFound) {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "service unavailable"})
		return false
	}
	if err != nil || user.EffectiveRole() != model.RolePartner {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "only partners have partner alerts"})
		return false
	}
	return true
}

func (h *Handler) GetPartnerAlerts(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	if !h.isPartner(w, userID) {
		return
	}
	pref, err := h.store.GetPartnerAlerts(userID)
	if err != nil {
		log.Printf("get partner alerts: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, pref)
}

func validClock(v string) bool {
	_, err := time.Parse("15:04", v)
	return err == nil && len(v) == 5
}

func (h *Handler) UpsertPartnerAlerts(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	if !h.isPartner(w, userID) {
		return
	}
	// Pre-fill defaults so older clients that omit newer fields (e.g.
	// pill_repeat_minutes) keep working instead of failing validation on 0.
	pref := model.DefaultPartnerAlertPreference()
	if err := json.NewDecoder(r.Body).Decode(&pref); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if !validClock(pref.PMSTime) || !validClock(pref.PillTime) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "times must use HH:MM in 24-hour format"})
		return
	}
	if !model.ValidPillRepeatMinutes(pref.PillRepeatMinutes) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "pill_repeat_minutes must be between 1 and 120"})
		return
	}
	saved, err := h.store.UpsertPartnerAlerts(userID, pref)
	if err != nil {
		log.Printf("upsert partner alerts: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, saved)
}
