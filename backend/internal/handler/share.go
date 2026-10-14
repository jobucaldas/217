package handler

import (
	"encoding/json"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"

	"217/backend/internal/auth"
	"217/backend/internal/model"
)

func (h *Handler) sessionPayload(user *model.User) map[string]interface{} {
	share, err := h.store.GetShareState(user.ID)
	if err != nil {
		log.Printf("share state error: %v", err)
		share = &model.ShareState{
			Status:          model.ShareNone,
			CanEditCalendar: user.EffectiveRole() == model.RoleOwner,
		}
	}
	user.Role = user.EffectiveRole()
	return map[string]interface{}{
		"user":  user,
		"share": h.withInviteURL(share),
		"consent": map[string]interface{}{
			"version":  model.ConsentVersion,
			"required": !user.HasConsent(),
		},
	}
}

// RecordConsent stores the user's agreement to the privacy notice version
// the app showed; an outdated version is refused so the new text is shown.
func (h *Handler) RecordConsent(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Version int `json:"version"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if body.Version != model.ConsentVersion {
		writeJSON(w, http.StatusConflict, map[string]interface{}{
			"error": "privacy notice changed", "consent_version": model.ConsentVersion,
		})
		return
	}
	user, err := h.store.RecordConsent(getUserID(r), body.Version)
	if err != nil {
		log.Printf("record consent: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, h.sessionPayload(user))
}

// ExportAccount returns everything stored about the caller as a JSON file.
func (h *Handler) ExportAccount(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	user, err := h.store.GetUserByID(userID)
	if err != nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}
	out := model.AccountExport{ExportedAt: time.Now().UTC(), User: user}
	fail := func(what string, err error) {
		log.Printf("export %s: %v", what, err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
	}
	if out.Share, err = h.store.GetShareState(userID); err != nil {
		fail("share", err)
		return
	}
	if out.Entries, err = h.store.ListAllEntries(userID); err != nil {
		fail("entries", err)
		return
	}
	out.NotesReceived = []*model.PartnerNote{}
	if out.NotesReceived, err = h.store.ListReceivedPartnerNotes(userID); err != nil {
		fail("inbox", err)
		return
	}
	if out.NotesSent, err = h.store.ListSentPartnerNotes(userID); err != nil {
		fail("sent notes", err)
		return
	}
	if out.Reminder, err = h.store.GetReminderPreference(userID); err != nil {
		fail("reminder", err)
		return
	}
	if out.PartnerAlerts, err = h.store.GetPartnerAlerts(userID); err != nil {
		fail("partner alerts", err)
		return
	}
	if out.Shares, err = h.store.ListAccountShares(userID); err != nil {
		fail("shares", err)
		return
	}
	if out.PushSubscriptions, err = h.store.ListAccountSubscriptions(userID); err != nil {
		fail("subscriptions", err)
		return
	}
	w.Header().Set("Content-Disposition", `attachment; filename="217-data-`+out.ExportedAt.Format("2006-01-02")+`.json"`)
	writeJSON(w, http.StatusOK, out)
}

// withInviteURL adds the shareable web link for an open invite, e.g.
// https://217.example.com/?invite=ABCD1234. The web app reads ?invite= and
// offers to join after sign-in.
func (h *Handler) withInviteURL(state *model.ShareState) *model.ShareState {
	if state == nil || state.Status != model.ShareOpen || state.InviteCode == "" {
		return state
	}
	base := strings.TrimRight(h.appBaseURL, "/")
	if base == "" {
		return state
	}
	state.InviteURL = base + "/?invite=" + url.QueryEscape(state.InviteCode)
	return state
}

func (h *Handler) DeleteAccount(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	if userID == "" {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	subject, err := h.store.WorkOSSubject(userID)
	if err != nil {
		log.Printf("delete account workos subject lookup: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "could not resolve WorkOS identity; account not deleted",
		})
		return
	}
	// Without WORKOS_API_KEY the sign-in identity stays with WorkOS, but the
	// data here (the sensitive part) is still deleted: the right to erasure
	// must not hinge on optional server configuration.
	deleter, canDelete := h.oauthProvider.(auth.WorkOSUserDeleter)
	if c, ok := h.oauthProvider.(auth.UserDeleteConfigurer); ok && !c.CanDeleteUsers() {
		canDelete = false
	}
	if subject != "" && canDelete {
		if err := deleter.DeleteUser(r.Context(), subject); err != nil {
			log.Printf("delete account workos user %s: %v", subject, err)
			writeJSON(w, http.StatusBadGateway, map[string]string{
				"error": "failed to delete WorkOS user; account not deleted",
			})
			return
		}
	} else if subject != "" {
		log.Printf("delete account %s: WorkOS identity kept (WORKOS_API_KEY not set or provider unavailable)", userID)
	}

	if err := h.store.DeleteUser(userID); err != nil {
		if strings.Contains(err.Error(), "not found") {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "user not found"})
			return
		}
		log.Printf("delete account error: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to delete local account data",
		})
		return
	}
	http.SetCookie(w, h.clearSessionCookie())
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) GetShare(w http.ResponseWriter, r *http.Request) {
	state, err := h.store.GetShareState(getUserID(r))
	if err != nil {
		log.Printf("get share: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, h.withInviteURL(state))
}

func (h *Handler) EnableShare(w http.ResponseWriter, r *http.Request) {
	state, err := h.store.EnableShare(getUserID(r))
	if err != nil {
		if strings.Contains(err.Error(), "only calendar owners") {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": err.Error()})
			return
		}
		log.Printf("enable share: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, h.withInviteURL(state))
}

func (h *Handler) RevokeShare(w http.ResponseWriter, r *http.Request) {
	state, err := h.store.RevokeShare(getUserID(r))
	if err != nil {
		if strings.Contains(err.Error(), "only calendar owners") {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": err.Error()})
			return
		}
		log.Printf("revoke share: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, h.withInviteURL(state))
}

func (h *Handler) AcceptShare(w http.ResponseWriter, r *http.Request) {
	if !h.inviteLimiter.allow("user:"+getUserID(r)) || !h.inviteLimiter.allow("ip:"+clientIP(r)) {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": "too many invite attempts; try again in a minute"})
		return
	}
	var body struct {
		Code string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	state, err := h.store.AcceptShare(getUserID(r), body.Code)
	if err != nil {
		msg := err.Error()
		switch {
		case msg == "calendar owner consent required":
			writeJSON(w, http.StatusForbidden, map[string]string{"error": msg})
		case strings.Contains(msg, "invite code"),
			strings.Contains(msg, "already linked"),
			strings.Contains(msg, "cannot accept"),
			strings.Contains(msg, "calendar owners"):
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": msg})
		default:
			log.Printf("accept share: %v", err)
			http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		}
		return
	}
	writeJSON(w, http.StatusOK, state)
}

func (h *Handler) ListInbox(w http.ResponseWriter, r *http.Request) {
	notes, err := h.store.ListInboxNotes(getUserID(r))
	if err != nil {
		if strings.Contains(err.Error(), "only owners") {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": err.Error()})
			return
		}
		log.Printf("list inbox: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"notes": notes})
}

func (h *Handler) CreatePartnerNote(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Body string `json:"body"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	note, err := h.store.CreatePartnerNote(getUserID(r), body.Body)
	if err != nil {
		msg := err.Error()
		switch {
		case msg == "calendar owner consent required",
			strings.Contains(msg, "only partners"), strings.Contains(msg, "share inactive"):
			writeJSON(w, http.StatusForbidden, map[string]string{"error": msg})
		case strings.Contains(msg, "required"), strings.Contains(msg, "too long"):
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": msg})
		default:
			log.Printf("create partner note: %v", err)
			http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		}
		return
	}
	writeJSON(w, http.StatusCreated, note)
}

func (h *Handler) MarkInboxNoteRead(w http.ResponseWriter, r *http.Request) {
	noteID := r.PathValue("id")
	if noteID == "" {
		http.Error(w, `{"error":"missing note id"}`, http.StatusBadRequest)
		return
	}
	if err := h.store.MarkInboxNoteRead(getUserID(r), noteID); err != nil {
		if strings.Contains(err.Error(), "not found") {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "note not found"})
			return
		}
		log.Printf("mark inbox note: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// calendarSubject resolves whose entries the caller may read.
func (h *Handler) calendarSubject(userID string) (string, error) {
	return h.store.CalendarSubjectID(userID)
}

func (h *Handler) requireCalendarEdit(userID string) bool {
	state, err := h.store.GetShareState(userID)
	if err != nil {
		return false
	}
	return state.CanEditCalendar
}
