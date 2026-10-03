package handler

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"217/backend/internal/cycle"
	"217/backend/internal/model"
)

// writeCalendarSubjectError explains why the caller has no calendar to read.
func writeCalendarSubjectError(w http.ResponseWriter, err error) {
	msg := "share inactive"
	if strings.Contains(err.Error(), "role not chosen") {
		msg = "role not chosen"
	}
	writeJSON(w, http.StatusForbidden, map[string]string{"error": msg})
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
	writeJSON(w, http.StatusOK, h.sessionPayload(user))
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
	writeJSON(w, http.StatusOK, cycle.Predict(days, today))
}

func (h *Handler) isPartner(userID string) bool {
	user, err := h.store.GetUserByID(userID)
	return err == nil && user.EffectiveRole() == model.RolePartner
}

func (h *Handler) GetPartnerAlerts(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	if !h.isPartner(userID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "only partners have partner alerts"})
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
	if !h.isPartner(userID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "only partners have partner alerts"})
		return
	}
	var pref model.PartnerAlertPreference
	if err := json.NewDecoder(r.Body).Decode(&pref); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if !validClock(pref.PMSTime) || !validClock(pref.PillTime) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "times must use HH:MM in 24-hour format"})
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
