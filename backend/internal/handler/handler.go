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

const (
	userIDKey  contextKey = "userID"
	consentKey contextKey = "consent"
)

const oauthBindingCookie = "217_oauth_binding"

const (
	maxSessionDuration = 7 * 24 * time.Hour
	minSessionDuration = 15 * time.Minute
	defaultAuthLimit   = 30
	// Invite codes are 8 chars from a 32-letter alphabet; cap guesses per
	// account and per address so codes can't be brute-forced.
	inviteAcceptLimit = 10
)

type Handler struct {
	store           store.Store
	vapidPublicKey  string
	sessionCookie   string
	sessionDuration time.Duration
	oauthProvider   auth.OAuthProvider
	appBaseURL      string
	allowedOrigins  []string
	authLimiter     *ipRateLimiter
	inviteLimiter   *ipRateLimiter
	privacyContact  string
}

func New(s store.Store) *Handler {
	return &Handler{
		store:           s,
		sessionCookie:   "217_session",
		sessionDuration: maxSessionDuration,
		authLimiter:     newIPRateLimiter(defaultAuthLimit, time.Minute),
		inviteLimiter:   newIPRateLimiter(inviteAcceptLimit, time.Minute),
	}
}

func NewWithVAPID(s store.Store, publicKey string) *Handler {
	h := New(s)
	h.vapidPublicKey = publicKey
	return h
}

func (h *Handler) SetSessionCookieName(name string) {
	if name != "" {
		h.sessionCookie = name
	}
}
func (h *Handler) SetSessionDuration(d time.Duration) {
	if d < minSessionDuration {
		d = minSessionDuration
	}
	if d > maxSessionDuration {
		d = maxSessionDuration
	}
	h.sessionDuration = d
}
func (h *Handler) SetRateLimit(limit int) {
	h.authLimiter = newIPRateLimiter(limit, time.Minute)
}
func (h *Handler) SetOAuthProvider(p auth.OAuthProvider) { h.oauthProvider = p }

// SetPrivacyContact sets who answers privacy requests for this server
// (the controller or its data protection officer): an email or a URL.
func (h *Handler) SetPrivacyContact(contact string) { h.privacyContact = strings.TrimSpace(contact) }
func (h *Handler) SetAppBaseURL(u string)           { h.appBaseURL = u }

// SetAllowedOrigins sets the extra public origins (besides the app base URL)
// that may start browser sign-in and send same-origin cookie requests.
func (h *Handler) SetAllowedOrigins(origins []string) { h.allowedOrigins = origins }

// browserOrigins lists the canonical origin first, then the extra allowed ones.
func (h *Handler) browserOrigins() []string {
	canonical := h.appOrigin()
	if canonical == "" {
		return nil
	}
	out := []string{canonical}
	for _, o := range h.allowedOrigins {
		if o != canonical {
			out = append(out, o)
		}
	}
	return out
}

// requestOrigin picks the allowlisted origin serving this request, derived
// from X-Forwarded-Host (set by the trusted proxy) or Host. Anything not on
// the allowlist falls back to the canonical origin, so a spoofed host is
// never reflected into a redirect URI.
func (h *Handler) requestOrigin(r *http.Request) string {
	origins := h.browserOrigins()
	host := r.Host
	if fwd := r.Header.Get("X-Forwarded-Host"); fwd != "" {
		host, _, _ = strings.Cut(fwd, ",")
	}
	if o := auth.MatchOriginHost(origins, host); o != "" {
		return o
	}
	return h.appOrigin()
}

func (h *Handler) authkitEnabled() bool { return h.oauthProvider != nil }

// AuthConfig reports which sign-in modes the API exposes. With AuthKit on it
// also reports the public client ID, which the Android app signs in with.
func (h *Handler) AuthConfig(w http.ResponseWriter, r *http.Request) {
	body := map[string]interface{}{
		"authkit":  h.authkitEnabled(),
		"password": false, // password register/login stay disabled for AuthKit deployments
	}
	if reporter, ok := h.oauthProvider.(auth.ClientIDReporter); ok {
		body["workos_client_id"] = reporter.ClientID()
	}
	body["consent_version"] = model.ConsentVersion
	if cfg, ok := h.oauthProvider.(auth.UserDeleteConfigurer); ok {
		body["workos_user_deletion"] = cfg.CanDeleteUsers()
	} else {
		body["workos_user_deletion"] = false
	}
	if h.privacyContact != "" {
		body["privacy_contact"] = h.privacyContact
	}
	writeJSON(w, http.StatusOK, body)
}

// Register is disabled when AuthKit is the product auth path.
func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	h.rejectPasswordAuth(w)
}

// Login is disabled when AuthKit is the product auth path.
func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	if !h.authLimiter.allow("login:" + clientIP(r)) {
		http.Error(w, `{"error":"rate limited"}`, http.StatusTooManyRequests)
		return
	}
	h.rejectPasswordAuth(w)
}

func (h *Handler) rejectPasswordAuth(w http.ResponseWriter) {
	writeJSON(w, http.StatusForbidden, map[string]string{
		"error": "password authentication is disabled; use WorkOS AuthKit",
	})
}

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
	return &http.Cookie{Name: oauthBindingCookie, Value: value, Path: "/api/auth/workos/callback", HttpOnly: true,
		Secure: h.sessionCookieSecure(), SameSite: http.SameSiteLaxMode, Expires: expires, MaxAge: 300}
}

func (h *Handler) clearOAuthBindingCookie() *http.Cookie {
	return &http.Cookie{Name: oauthBindingCookie, Path: "/api/auth/workos/callback", HttpOnly: true,
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
	for _, allowed := range h.browserOrigins() {
		if origin != "" && origin == allowed {
			return true
		}
	}
	return false
}

func isUnsafeMethod(method string) bool {
	switch method {
	case http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete:
		return true
	default:
		return false
	}
}

func (h *Handler) sessionTokenFromRequest(r *http.Request) (string, bool) {
	if cookie, err := r.Cookie(h.sessionCookie); err == nil && cookie.Value != "" {
		return cookie.Value, true
	}
	authz := r.Header.Get("Authorization")
	if strings.HasPrefix(strings.ToLower(authz), "bearer ") {
		token := strings.TrimSpace(authz[7:])
		if token != "" {
			return token, true
		}
	}
	return "", false
}

func (h *Handler) AuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, ok := h.sessionTokenFromRequest(r)
		if !ok {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		user, err := h.store.GetUserBySession(token)
		if err != nil {
			http.SetCookie(w, h.clearSessionCookie())
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		_, cookieErr := r.Cookie(h.sessionCookie)
		if isUnsafeMethod(r.Method) && cookieErr == nil && !h.sameOriginAllowed(r) {
			http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
			return
		}
		ctx := context.WithValue(r.Context(), userIDKey, user.ID)
		ctx = context.WithValue(ctx, consentKey, user.HasConsent())
		next(w, r.WithContext(ctx))
	}
}

// ConsentMiddleware is AuthMiddleware for endpoints that process personal
// data: they wait until the user agreed to the current privacy notice.
// Account deletion, export and consent itself stay reachable without it.
func (h *Handler) ConsentMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return h.AuthMiddleware(func(w http.ResponseWriter, r *http.Request) {
		if ok, _ := r.Context().Value(consentKey).(bool); !ok {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "consent required"})
			return
		}
		next(w, r)
	})
}

func getUserID(r *http.Request) string {
	if uid, ok := r.Context().Value(userIDKey).(string); ok {
		return uid
	}
	return ""
}

// --- Session & OAuth handlers ---

func (h *Handler) CurrentSession(w http.ResponseWriter, r *http.Request) {
	if token, ok := h.sessionTokenFromRequest(r); ok {
		user, err := h.store.GetUserBySession(token)
		if err == nil {
			writeJSON(w, http.StatusOK, h.sessionPayload(user))
			return
		}
		http.SetCookie(w, h.clearSessionCookie())
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"user": nil, "share": nil})
}

func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	_, cookieErr := r.Cookie(h.sessionCookie)
	if cookieErr == nil && !h.sameOriginAllowed(r) {
		http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
		return
	}
	if token, ok := h.sessionTokenFromRequest(r); ok {
		// An expired Bearer session no longer leads to its device key: answer
		// 401 so the app renews with the key and logs out again, revoking it.
		if _, err := h.store.GetUserBySession(token); err != nil && cookieErr != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
		// A device key ends with the session: signing out means signing in again.
		if err := h.store.DeleteSessionAndDevice(token); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "could not log out; retry"})
			return
		}
	}
	http.SetCookie(w, h.clearSessionCookie())
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) StartWorkOSOAuth(w http.ResponseWriter, r *http.Request) {
	if !h.authLimiter.allow("workos:" + clientIP(r)) {
		http.Error(w, `{"error":"rate limited"}`, http.StatusTooManyRequests)
		return
	}
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
	origin := h.requestOrigin(r)
	redirectURI := ""
	if origin != "" {
		redirectURI = origin + auth.BrowserCallbackPath
	}
	if err := h.store.CreateOAuthAttempt(state, binding, verifier, nonce, redirectURI, expires); err != nil {
		log.Printf("create oauth attempt failed: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	http.SetCookie(w, h.oauthBindingCookieValue(binding, expires))
	var authURL string
	if p, ok := h.oauthProvider.(auth.RedirectAuthCodeURLer); ok && redirectURI != "" {
		authURL = p.AuthCodeURLForRedirect(state, pkceChallengeS256(verifier), nonce, redirectURI)
	} else {
		authURL = h.oauthProvider.AuthCodeURL(state, pkceChallengeS256(verifier), nonce)
	}
	if authURL == "" {
		http.Error(w, `{"error":"cannot build authorization url"}`, http.StatusInternalServerError)
		return
	}
	// JSON + Set-Cookie (not a 302 bounce). Flutter web fetches this on the
	// Entrar click, then navigates to AuthKit — no second "continue" screen.
	// Cookie is set on a same-origin response, so Chromium bounce-tracking does
	// not drop 217_oauth_binding the way a redirect chain would.
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, map[string]string{"auth_url": authURL})
}

// createSessionForUser opens a session; with deviceKeyID it is bound to
// that device key (Bearer clients that renew it themselves).
func (h *Handler) createSessionForUser(w http.ResponseWriter, r *http.Request, user *model.User, deviceKeyID string) (string, error) {
	sessionToken, err := generateRandom(32)
	if err != nil {
		return "", err
	}
	expires := time.Now().UTC().Add(h.sessionDuration)
	if deviceKeyID != "" {
		err = h.store.CreateDeviceSession(user.ID, deviceKeyID, sessionToken, expires)
	} else {
		err = h.store.CreateSession(user.ID, sessionToken, expires)
	}
	if err != nil {
		return "", err
	}
	http.SetCookie(w, h.sessionCookieValue(sessionToken, expires))
	return sessionToken, nil
}

func (h *Handler) linkWorkOSUser(w http.ResponseWriter, userInfo *auth.OAuthUserInfo) (*model.User, bool) {
	if userInfo == nil || !userInfo.EmailVerified || userInfo.Subject == "" || userInfo.Email == "" {
		http.Error(w, `{"error":"workos email not verified"}`, http.StatusForbidden)
		return nil, false
	}
	user, err := h.store.LinkWorkOSIdentity(userInfo.Subject, userInfo.Email, userInfo.Name, userInfo.AuthoritativeEmail())
	if err != nil {
		log.Printf("link workos identity failed: %v", err)
		http.Error(w, `{"error":"Unable to link this WorkOS account. Contact the app operator for account ownership verification. / Não foi possível vincular esta conta WorkOS. Contate o responsável pelo aplicativo para verificar a titularidade."}`, http.StatusForbidden)
		return nil, false
	}
	return user, true
}

func (h *Handler) WorkOSOAuthCallback(w http.ResponseWriter, r *http.Request) {
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
	// The token exchange must use the redirect URI the attempt started with.
	var userInfo *auth.OAuthUserInfo
	if exchanger, ok := h.oauthProvider.(auth.WorkOSExchanger); ok && attempt.RedirectURI != "" {
		userInfo, err = exchanger.ExchangeWithRedirect(r.Context(), code, attempt.CodeVerifier, attempt.RedirectURI)
	} else {
		userInfo, err = h.oauthProvider.Exchange(r.Context(), code, attempt.CodeVerifier, attempt.Nonce)
	}
	if err != nil {
		log.Printf("oauth exchange error: %v", err)
		http.Error(w, `{"error":"oauth exchange failed"}`, http.StatusBadRequest)
		return
	}
	user, ok := h.linkWorkOSUser(w, userInfo)
	if !ok {
		return
	}
	if _, err := h.createSessionForUser(w, r, user, ""); err != nil {
		log.Printf("create session failed: %v", err)
		http.Error(w, `{"error":"cannot create session"}`, http.StatusInternalServerError)
		return
	}
	redirectTo := strings.TrimSuffix(attempt.RedirectURI, auth.BrowserCallbackPath)
	if redirectTo == "" || redirectTo == attempt.RedirectURI && attempt.RedirectURI != "" {
		redirectTo = strings.TrimRight(h.appBaseURL, "/")
	}
	if redirectTo == "" {
		redirectTo = "/"
	}
	http.Redirect(w, r, redirectTo, http.StatusFound)
}

// ExchangeWorkOS handles native (Flutter) AuthKit PKCE completion.
// Native apps open AuthKit with a custom-scheme (Android) or loopback (desktop) redirect, then posts code+verifier here.
func (h *Handler) ExchangeWorkOS(w http.ResponseWriter, r *http.Request) {
	if !h.authLimiter.allow("workos-exchange:" + clientIP(r)) {
		http.Error(w, `{"error":"rate limited"}`, http.StatusTooManyRequests)
		return
	}
	if h.oauthProvider == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "oauth not configured"})
		return
	}
	var body struct {
		Code         string `json:"code"`
		CodeVerifier string `json:"code_verifier"`
		RedirectURI  string `json:"redirect_uri"`
		// Optional: base64 PKIX P-256 key from the Android Keystore, so the
		// app can renew its session later (see device.go).
		DevicePublicKey string `json:"device_public_key"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Code == "" || body.CodeVerifier == "" {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	var devicePublicKey []byte
	if body.DevicePublicKey != "" {
		key, err := parseDevicePublicKey(body.DevicePublicKey)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		devicePublicKey = key
	}
	if !auth.IsNativeRedirectURI(body.RedirectURI) {
		http.Error(w, `{"error":"invalid redirect uri"}`, http.StatusBadRequest)
		return
	}
	var (
		userInfo *auth.OAuthUserInfo
		err      error
	)
	if exchanger, ok := h.oauthProvider.(auth.WorkOSExchanger); ok && body.RedirectURI != "" {
		userInfo, err = exchanger.ExchangeWithRedirect(r.Context(), body.Code, body.CodeVerifier, body.RedirectURI)
	} else {
		userInfo, err = h.oauthProvider.Exchange(r.Context(), body.Code, body.CodeVerifier, "")
	}
	if err != nil {
		log.Printf("workos mobile exchange error: %v", err)
		http.Error(w, `{"error":"oauth exchange failed"}`, http.StatusBadRequest)
		return
	}
	user, ok := h.linkWorkOSUser(w, userInfo)
	if !ok {
		return
	}
	var deviceKeyID string
	if devicePublicKey != nil {
		if deviceKeyID, err = h.store.CreateDeviceKey(user.ID, devicePublicKey); err != nil {
			log.Printf("create device key failed: %v", err)
			http.Error(w, `{"error":"cannot create session"}`, http.StatusInternalServerError)
			return
		}
	}
	sessionToken, err := h.createSessionForUser(w, r, user, deviceKeyID)
	if err != nil {
		log.Printf("create session failed: %v", err)
		http.Error(w, `{"error":"cannot create session"}`, http.StatusInternalServerError)
		return
	}
	payload := h.sessionPayload(user)
	payload["session_token"] = sessionToken
	if deviceKeyID != "" {
		payload["device_key_id"] = deviceKeyID
	}
	writeJSON(w, http.StatusOK, payload)
}

// --- Entry handlers ---

func (h *Handler) ListEntries(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	subjectID, err := h.calendarSubject(userID)
	if err != nil {
		writeCalendarSubjectError(w, err)
		return
	}
	year, month := parseYearMonth(r)
	if year == 0 {
		now := time.Now().UTC()
		year, month = now.Year(), int(now.Month())
	}
	if err := h.requireSubjectConsent(w, userID, subjectID); err != nil {
		return
	}

	entries, err := h.store.ListEntries(subjectID, year, month)
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
	subjectID, err := h.calendarSubject(userID)
	if err != nil {
		writeCalendarSubjectError(w, err)
		return
	}
	date := r.PathValue("date")
	if date == "" {
		http.Error(w, `{"error":"missing date"}`, http.StatusBadRequest)
		return
	}

	if _, err := time.Parse("2006-01-02", date); err != nil {
		http.Error(w, `{"error":"invalid date format, use YYYY-MM-DD"}`, http.StatusBadRequest)
		return
	}
	if err := h.requireSubjectConsent(w, userID, subjectID); err != nil {
		return
	}

	entry, err := h.store.GetEntry(subjectID, date)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "entry not found"})
		return
	}
	writeJSON(w, http.StatusOK, entry)
}

func (h *Handler) UpsertEntry(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	if !h.requireCalendarEdit(userID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "calendar is read-only"})
		return
	}
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

func (h *Handler) DeleteEntry(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	if !h.requireCalendarEdit(userID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "calendar is read-only"})
		return
	}
	date := r.PathValue("date")
	if date == "" {
		http.Error(w, `{"error":"missing date"}`, http.StatusBadRequest)
		return
	}
	if _, err := time.Parse("2006-01-02", date); err != nil {
		http.Error(w, `{"error":"invalid date format, use YYYY-MM-DD"}`, http.StatusBadRequest)
		return
	}
	if err := h.store.DeleteEntry(userID, date); err != nil {
		if strings.Contains(err.Error(), "not found") {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "entry not found"})
			return
		}
		log.Printf("delete entry error: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) GetStats(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	subjectID, err := h.calendarSubject(userID)
	if err != nil {
		writeCalendarSubjectError(w, err)
		return
	}
	if err := h.requireSubjectConsent(w, userID, subjectID); err != nil {
		return
	}
	year, month := parseYearMonth(r)
	if year == 0 {
		now := time.Now().UTC()
		year, month = now.Year(), int(now.Month())
	}

	stats, err := h.store.GetStats(subjectID, year, month)
	if err != nil {
		log.Printf("stats error: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, stats)
}

// requireSubjectConsent protects a shared owner's calendar when the caller
// has consented but the owner has not agreed to the current notice.
func (h *Handler) requireSubjectConsent(w http.ResponseWriter, callerID, subjectID string) error {
	if callerID == subjectID {
		return nil
	}
	subject, err := h.store.GetUserByID(subjectID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return err
	}
	if !subject.HasConsent() {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "calendar owner consent required"})
		return fmt.Errorf("calendar owner consent required")
	}
	return nil
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
	userID := getUserID(r)
	// Start from the currently stored preference (defaults if none yet) so
	// older clients that omit repeat_enabled/repeat_minutes keep their
	// existing values instead of resetting them.
	preference, err := h.store.GetReminderPreference(userID)
	if err != nil {
		log.Printf("get reminder preference: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	if err := json.NewDecoder(r.Body).Decode(preference); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if err := validateReminderPreference(*preference); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	if !model.ValidRepeatMinutes(preference.RepeatMinutes) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "repeat_minutes must be between 1 and 120"})
		return
	}
	// Allow enabling without a web-push subscription so native clients can
	// schedule OS local notifications. Deliverable still reflects push readiness.
	result, err := h.store.UpsertReminderPreference(userID, *preference)
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
