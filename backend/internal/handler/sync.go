package handler

import (
	"errors"
	"log"
	"net/http"
	"strings"

	"217/backend/internal/synchub"
)

// SetSyncHub enables GET /api/sync/status; hub must be the one wrapping the store.
func (h *Handler) SetSyncHub(hub *synchub.Hub) { h.syncHub = hub }

// SyncStatus answers from memory for a cached session (no database), so
// apps can poll it cheaply and refetch only what a changed tag names.
func (h *Handler) SyncStatus(w http.ResponseWriter, r *http.Request) {
	if h.syncHub == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "sync status unavailable"})
		return
	}
	_, cookieErr := r.Cookie(h.sessionCookie)
	unauthorized := func() {
		if cookieErr == nil {
			http.SetCookie(w, h.clearSessionCookie())
		}
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
	}
	token, ok := h.sessionTokenFromRequest(r)
	if !ok {
		unauthorized()
		return
	}
	st, hit, err := h.syncHub.Cached(token)
	if !hit {
		if !h.syncMissLimiter.allow("sync:" + clientIP(r)) {
			http.Error(w, `{"error":"rate limited"}`, http.StatusTooManyRequests)
			return
		}
		st, err = h.syncHub.Load(token)
	}
	if errors.Is(err, synchub.ErrUnauthorized) {
		unauthorized()
		return
	}
	if err != nil {
		log.Printf("sync status: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	if !st.Consent {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "consent required"})
		return
	}
	w.Header().Set("ETag", `"`+st.ETag+`"`)
	if etagMatches(r.Header.Get("If-None-Match"), st.ETag) {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	writeJSON(w, http.StatusOK, st)
}

// etagMatches reports whether an If-None-Match list names etag (weak or strong).
func etagMatches(header, etag string) bool {
	for _, candidate := range strings.Split(header, ",") {
		candidate = strings.TrimSpace(candidate)
		candidate = strings.TrimPrefix(candidate, "W/")
		candidate = strings.Trim(candidate, `"`)
		if candidate == etag && etag != "" {
			return true
		}
	}
	return false
}
