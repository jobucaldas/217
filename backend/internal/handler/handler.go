package handler

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"217/backend/internal/auth"
	"217/backend/internal/model"
	"217/backend/internal/store"
)

type contextKey string

const userIDKey contextKey = "userID"

const oauthBindingCookie = "217_oauth_binding"

type Handler struct {
	store           store.Store
	vapidPublicKey  string
	sessionCookie   string
	sessionDuration time.Duration
	oauthProvider   auth.OAuthProvider
	appBaseURL      string
}

func New(s store.Store) *Handler {
	return &Handler{store: s, sessionCookie: "217_session", sessionDuration: 7 * 24 * time.Hour}
}

func NewWithVAPID(s store.Store, publicKey string) *Handler {
	return &Handler{store: s, vapidPublicKey: publicKey, sessionCookie: "217_session", sessionDuration: 7 * 24 * time.Hour}
}

func (h *Handler) SetSessionCookieName(name string) {
	if name != "" {
		h.sessionCookie = name
	}
}
func (h *Handler) SetSessionDuration(d time.Duration) {
	if d > 0 {
		h.sessionDuration = d
	}
}
func (h *Handler) SetOAuthProvider(p auth.OAuthProvider) { h.oauthProvider = p }
func (h *Handler) SetAppBaseURL(u string)                { h.appBaseURL = u }

func (h *Handler) sessionCookieSecure() bool {
	u, err := url.Parse(h.appBaseURL)
	return err == nil && u.Scheme == "https"
}

func (h *Handler) sessionCookieValue(token string, expires time.Time) *http.Cookie {
	return &http.Cookie{
		Name:     h.sessionCookie,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		Secure:   h.sessionCookieSecure(),
		SameSite: http.SameSiteLaxMode,
		Expires:  expires,
		MaxAge:   int(h.sessionDuration.Seconds()),
	}
}

func (h *Handler) clearSessionCookie() *http.Cookie {
	return &http.Cookie{
		Name:     h.sessionCookie,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		Secure:   h.sessionCookieSecure(),
		SameSite: http.SameSiteLaxMode,
		Expires:  time.Unix(0, 0),
		MaxAge:   -1,
	}
}

func (h *Handler) oauthBindingCookieValue(value string, expires time.Time) *http.Cookie {
	return &http.Cookie{Name: oauthBindingCookie, Value: value, Path: "/api/auth/google/callback", HttpOnly: true,
		Secure: h.sessionCookieSecure(), SameSite: http.SameSiteLaxMode, Expires: expires, MaxAge: 300}
}

func (h *Handler) clearOAuthBindingCookie() *http.Cookie {
	return &http.Cookie{Name: oauthBindingCookie, Path: "/api/auth/google/callback", HttpOnly: true,
		Secure: h.sessionCookieSecure(), SameSite: http.SameSiteLaxMode, Expires: time.Unix(0, 0), MaxAge: -1}
}

func (h *Handler) appOrigin() string {
	u, err := url.Parse(h.appBaseURL)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return ""
	}
	return u.Scheme + "://" + u.Host
}

func (h *Handler) sameOriginAllowed(r *http.Request) bool {
	if h.appOrigin() == "" {
		return true
	}
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	return origin == h.appOrigin()
}

func isUnsafeMethod(method string) bool {
	switch method {
	case http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete:
		return true
	default:
		return false
	}
}

func (h *Handler) AuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie(h.sessionCookie)
		if err != nil || cookie.Value == "" {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		user, err := h.store.GetUserBySession(cookie.Value)
		if err != nil {
			http.SetCookie(w, h.clearSessionCookie())
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		if isUnsafeMethod(r.Method) && !h.sameOriginAllowed(r) {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		ctx := context.WithValue(r.Context(), userIDKey, user.ID)
		next(w, r.WithContext(ctx))
	}
}

func getUserID(r *http.Request) string {
	if uid, ok := r.Context().Value(userIDKey).(string); ok {
		return uid
	}
	return ""
}

// --- Session & OAuth handlers ---

func (h *Handler) CurrentSession(w http.ResponseWriter, r *http.Request) {
	if cookie, err := r.Cookie(h.sessionCookie); err == nil && cookie.Value != "" {
		user, err := h.store.GetUserBySession(cookie.Value)
		if err == nil {
			writeJSON(w, http.StatusOK, map[string]interface{}{"user": user})
			return
		}
		http.SetCookie(w, h.clearSessionCookie())
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"user": nil})
}

func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	if !h.sameOriginAllowed(r) {
		http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
		return
	}
	if cookie, err := r.Cookie(h.sessionCookie); err == nil && cookie.Value != "" {
		if err := h.store.DeleteSession(cookie.Value); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "could not log out; retry"})
			return
		}
	}
	http.SetCookie(w, h.clearSessionCookie())
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) StartGoogleOAuth(w http.ResponseWriter, r *http.Request) {
	if h.oauthProvider == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "oauth not configured"})
		return
	}
	state, err := generateRandom(32)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	verifier, err := generateRandom(32)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	binding, err := generateRandom(32)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	nonce, err := generateRandom(32)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	expires := time.Now().UTC().Add(5 * time.Minute)
	if err := h.store.CreateOAuthAttempt(state, binding, verifier, nonce, expires); err != nil {
		log.Printf("create oauth attempt failed: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	http.SetCookie(w, h.oauthBindingCookieValue(binding, expires))
	authURL := h.oauthProvider.AuthCodeURL(state, pkceChallengeS256(verifier), nonce)
	http.Redirect(w, r, authURL, http.StatusFound)
}

func (h *Handler) GoogleOAuthCallback(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, h.clearOAuthBindingCookie())
	if h.oauthProvider == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "oauth not configured"})
		return
	}
	q := r.URL.Query()
	code := q.Get("code")
	state := q.Get("state")
	if code == "" || state == "" {
		http.Error(w, `{"error":"missing code or state"}`, http.StatusBadRequest)
		return
	}
	bindingCookie, cookieErr := r.Cookie(oauthBindingCookie)
	if cookieErr != nil || bindingCookie.Value == "" {
		http.Error(w, `{"error":"invalid or expired state"}`, http.StatusBadRequest)
		return
	}
	attempt, err := h.store.ConsumeOAuthAttempt(state, bindingCookie.Value)
	if err != nil {
		http.Error(w, `{"error":"invalid or expired state"}`, http.StatusBadRequest)
		return
	}
	userInfo, err := h.oauthProvider.Exchange(r.Context(), code, attempt.CodeVerifier, attempt.Nonce)
	if err != nil {
		log.Printf("oauth exchange error: %v", err)
		http.Error(w, `{"error":"oauth exchange failed"}`, http.StatusBadRequest)
		return
	}
	if userInfo == nil || !userInfo.EmailVerified || userInfo.Subject == "" || userInfo.Email == "" {
		http.Error(w, `{"error":"google email not verified"}`, http.StatusForbidden)
		return
	}
	user, err := h.store.LinkGoogleIdentity(userInfo.Subject, userInfo.Email, userInfo.Name, userInfo.AuthoritativeEmail())
	if err != nil {
		log.Printf("link google identity failed: %v", err)
		http.Error(w, `{"error":"Unable to link this Google account. Contact the app operator for account ownership verification. / Não foi possível vincular esta conta Google. Contate o responsável pelo aplicativo para verificar a titularidade."}`, http.StatusForbidden)
		return
	}
	sessionToken, err := generateRandom(32)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	expires := time.Now().UTC().Add(h.sessionDuration)
	if err := h.store.CreateSession(user.ID, sessionToken, expires, r.UserAgent(), r.RemoteAddr); err != nil {
		log.Printf("create session failed: %v", err)
		http.Error(w, `{"error":"cannot create session"}`, http.StatusInternalServerError)
		return
	}
	http.SetCookie(w, h.sessionCookieValue(sessionToken, expires))
	redirectTo := strings.TrimRight(h.appBaseURL, "/")
	if redirectTo == "" {
		redirectTo = "/"
	}
	http.Redirect(w, r, redirectTo, http.StatusFound)
}

// --- Entry handlers ---

func (h *Handler) ListEntries(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	year, month := parseYearMonth(r)
	if year == 0 {
		now := time.Now().UTC()
		year, month = now.Year(), int(now.Month())
	}

	entries, err := h.store.ListEntries(userID, year, month)
	if err != nil {
		log.Printf("list entries error: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}

	resp := model.MonthEntries{
		Year:    year,
		Month:   month,
		Entries: entries,
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) GetEntry(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	date := r.PathValue("date")
	if date == "" {
		http.Error(w, `{"error":"missing date"}`, http.StatusBadRequest)
		return
	}

	if _, err := time.Parse("2006-01-02", date); err != nil {
		http.Error(w, `{"error":"invalid date format, use YYYY-MM-DD"}`, http.StatusBadRequest)
		return
	}

	entry, err := h.store.GetEntry(userID, date)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "entry not found"})
		return
	}
	writeJSON(w, http.StatusOK, entry)
}

func (h *Handler) UpsertEntry(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	date := r.PathValue("date")
	if date == "" {
		http.Error(w, `{"error":"missing date"}`, http.StatusBadRequest)
		return
	}

	if _, err := time.Parse("2006-01-02", date); err != nil {
		http.Error(w, `{"error":"invalid date format, use YYYY-MM-DD"}`, http.StatusBadRequest)
		return
	}

	var req model.UpsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	entry, err := h.store.UpsertEntry(userID, date, req)
	if err != nil {
		log.Printf("upsert error: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, entry)
}

func (h *Handler) GetStats(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	year, month := parseYearMonth(r)
	if year == 0 {
		now := time.Now().UTC()
		year, month = now.Year(), int(now.Month())
	}

	stats, err := h.store.GetStats(userID, year, month)
	if err != nil {
		log.Printf("stats error: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, stats)
}

// --- Reminder handlers ---

func (h *Handler) GetReminderPreference(w http.ResponseWriter, r *http.Request) {
	preference, err := h.store.GetReminderPreference(getUserID(r))
	if err != nil {
		log.Printf("get reminder preference: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, preference)
}

func validateReminderPreference(preference model.ReminderPreference) error {
	if _, err := time.Parse("15:04", preference.Time); err != nil || len(preference.Time) != 5 {
		return fmt.Errorf("time must use HH:MM in 24-hour format")
	}
	if len(preference.Timezone) > 100 {
		return fmt.Errorf("timezone is too long")
	}
	if _, err := time.LoadLocation(preference.Timezone); err != nil {
		return fmt.Errorf("timezone must be a valid IANA timezone")
	}
	return nil
}

func (h *Handler) UpsertReminderPreference(w http.ResponseWriter, r *http.Request) {
	var preference model.ReminderPreference
	if err := json.NewDecoder(r.Body).Decode(&preference); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if err := validateReminderPreference(preference); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	if preference.Enabled {
		count, err := h.store.CountPushSubscriptions(getUserID(r))
		if err != nil {
			http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
			return
		}
		if count == 0 {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "enable notifications on this device before enabling reminders"})
			return
		}
	}
	result, err := h.store.UpsertReminderPreference(getUserID(r), preference)
	if err != nil {
		log.Printf("upsert reminder preference: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (h *Handler) VAPIDPublicKey(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"configured": h.vapidPublicKey != "",
		"public_key": h.vapidPublicKey,
	})
}

func validPushEndpoint(endpoint *url.URL) bool {
	host := strings.ToLower(endpoint.Hostname())
	if endpoint.Scheme != "https" || host == "" || host == "localhost" || strings.HasSuffix(host, ".localhost") || strings.HasSuffix(host, ".local") {
		return false
	}
	if ip := net.ParseIP(host); ip != nil && (ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() || ip.IsMulticast()) {
		return false
	}
	return true
}

func decodePushKey(value string, expectedLength int) bool {
	decoded, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(value, "="))
	return err == nil && len(decoded) == expectedLength
}

func (h *Handler) SavePushSubscription(w http.ResponseWriter, r *http.Request) {
	if h.vapidPublicKey == "" {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "push notifications are not configured on this server"})
		return
	}
	var request model.PushSubscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	endpoint, err := url.ParseRequestURI(request.Endpoint)
	if err != nil || !validPushEndpoint(endpoint) || len(request.Endpoint) > 2048 ||
		!decodePushKey(request.Keys.P256DH, 65) || !decodePushKey(request.Keys.Auth, 16) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid push subscription"})
		return
	}
	_, err = h.store.SavePushSubscription(getUserID(r), request)
	if err != nil {
		log.Printf("save push subscription: %v", err)
		writeJSON(w, http.StatusConflict, map[string]string{"error": "could not save push subscription"})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"status": "subscribed"})
}

func (h *Handler) DeletePushSubscription(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Endpoint string `json:"endpoint"`
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil || request.Endpoint == "" {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if err := h.store.DeletePushSubscription(getUserID(r), request.Endpoint); err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func parseYearMonth(r *http.Request) (int, int) {
	q := r.URL.Query()
	yearStr := q.Get("year")
	monthStr := q.Get("month")
	if yearStr == "" || monthStr == "" {
		return 0, 0
	}
	year, err := strconv.Atoi(yearStr)
	if err != nil {
		return 0, 0
	}
	month, err := strconv.Atoi(monthStr)
	if err != nil || month < 1 || month > 12 {
		return 0, 0
	}
	return year, month
}

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(data); err != nil {
		log.Printf("error encoding response: %v", err)
	}
}

func generateRandom(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func pkceChallengeS256(verifier string) string {
	h := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(h[:])
}

func hashHex(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}
