package handler

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"html"
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

const (
	maxSessionDuration = 7 * 24 * time.Hour
	minSessionDuration = 15 * time.Minute
	defaultAuthLimit   = 30
)

type Handler struct {
	store           store.Store
	vapidPublicKey  string
	sessionCookie   string
	sessionDuration time.Duration
	oauthProvider   auth.OAuthProvider
	appBaseURL      string
	authLimiter     *ipRateLimiter
}

func New(s store.Store) *Handler {
	return &Handler{
		store:           s,
		sessionCookie:   "217_session",
		sessionDuration: maxSessionDuration,
		authLimiter:     newIPRateLimiter(defaultAuthLimit, time.Minute),
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
func (h *Handler) SetAppBaseURL(u string)                { h.appBaseURL = u }

func (h *Handler) authkitEnabled() bool { return h.oauthProvider != nil }

// AuthConfig reports which sign-in modes the API exposes.
func (h *Handler) AuthConfig(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"authkit":  h.authkitEnabled(),
		"password": false, // password register/login stay disabled for AuthKit deployments
	})
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
	if !h.sameOriginAllowed(r) {
		http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
		return
	}
	if token, ok := h.sessionTokenFromRequest(r); ok {
		if err := h.store.DeleteSession(token); err != nil {
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
	if err := h.store.CreateOAuthAttempt(state, binding, verifier, nonce, expires); err != nil {
		log.Printf("create oauth attempt failed: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	http.SetCookie(w, h.oauthBindingCookieValue(binding, expires))
	authURL := h.oauthProvider.AuthCodeURL(state, pkceChallengeS256(verifier), nonce)
	if authURL == "" {
		http.Error(w, `{"error":"cannot build authorization url"}`, http.StatusInternalServerError)
		return
	}
	// Serve a same-origin HTML document (not a 302 bounce) so Chromium keeps the
	// HttpOnly binding cookie across the subsequent navigation to AuthKit.
	writeOAuthContinuePage(w, r, authURL)
}

func writeOAuthContinuePage(w http.ResponseWriter, r *http.Request, authURL string) {
	jsURL, err := json.Marshal(authURL)
	if err != nil {
		http.Error(w, `{"error":"cannot build authorization url"}`, http.StatusInternalServerError)
		return
	}
	href := html.EscapeString(authURL)
	pt := prefersPortuguese(r)
	lang := "en"
	title := "Continue sign-in"
	brand := "217"
	tagline := "contraceptive calendar"
	bodyCopy := "Continue to finish signing in to 217."
	cta := "Continue"
	if pt {
		lang = "pt"
		title = "Continuar entrada"
		tagline = "calendário de anticoncepcional"
		bodyCopy = "Continue para concluir a entrada no 217."
		cta = "Continuar"
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)
	// Require a same-origin click before leaving for AuthKit. Chromium bounce
	// tracking drops cookies set on automatic cross-site hops (302, meta-refresh,
	// or short setTimeout redirects); a user gesture keeps 217_oauth_binding.
	// Visual language matches the Flutter AuthScreen + AuthKit branding (azure
	// accents, pinned neutrals, Fraunces brand, Source Sans body).
	_, _ = fmt.Fprintf(w, `<!DOCTYPE html>
<html lang="%s">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600&family=Source+Sans+3:wght@400;600;700&display=swap" rel="stylesheet">
<style>
  :root {
    color-scheme: light dark;
    --scaffold: #F5F5F4;
    --on-surface: #1C1917;
    --on-variant: #57534E;
    --primary: #2563EB;
    --on-primary: #FFFFFF;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --scaffold: #121212;
      --on-surface: #F5F5F5;
      --on-variant: #D4D4D4;
      --primary: #60A5FA;
      --on-primary: #0B1220;
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    min-height: 100vh;
    display: grid;
    place-items: center;
    background: var(--scaffold);
    color: var(--on-surface);
    font-family: "Source Sans 3", system-ui, sans-serif;
  }
  main {
    text-align: center;
    padding: 2rem 1.75rem;
    max-width: 22.5rem;
    width: 100%%;
  }
  .brand {
    font-family: "Fraunces", Georgia, serif;
    font-weight: 600;
    font-size: 3.5rem;
    letter-spacing: -0.04em;
    line-height: 1;
    margin: 0 0 0.85rem;
  }
  .tagline {
    margin: 0 0 1.15rem;
    color: var(--on-variant);
    font-size: 1.05rem;
    line-height: 1.4;
  }
  .copy {
    margin: 0 0 1.75rem;
    color: var(--on-variant);
    font-size: 0.95rem;
    line-height: 1.45;
  }
  a.continue {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 3.25rem;
    padding: 0.85rem 1.25rem;
    border-radius: 14px;
    background: var(--primary);
    color: var(--on-primary);
    font-weight: 700;
    font-size: 1rem;
    text-decoration: none;
  }
</style>
</head>
<body>
<main>
  <h1 class="brand">%s</h1>
  <p class="tagline">%s</p>
  <p class="copy">%s</p>
  <p><a class="continue" id="continue" href="%s" rel="noopener">%s</a></p>
</main>
<script>
// Expose URL for tests; navigation is click-driven only.
window.__WORKOS_AUTH_URL__ = %s;
</script>
</body>
</html>`, lang, html.EscapeString(title), html.EscapeString(brand),
		html.EscapeString(tagline), html.EscapeString(bodyCopy), href,
		html.EscapeString(cta), jsURL)
}

func prefersPortuguese(r *http.Request) bool {
	if r == nil {
		return true
	}
	al := strings.ToLower(r.Header.Get("Accept-Language"))
	if al == "" {
		return true
	}
	// Prefer the first tag that looks like pt* or en*.
	for _, part := range strings.Split(al, ",") {
		tag := strings.TrimSpace(strings.Split(part, ";")[0])
		if strings.HasPrefix(tag, "pt") {
			return true
		}
		if strings.HasPrefix(tag, "en") {
			return false
		}
	}
	return true
}

func (h *Handler) createSessionForUser(w http.ResponseWriter, r *http.Request, user *model.User) (string, error) {
	sessionToken, err := generateRandom(32)
	if err != nil {
		return "", err
	}
	expires := time.Now().UTC().Add(h.sessionDuration)
	if err := h.store.CreateSession(user.ID, sessionToken, expires, r.UserAgent(), r.RemoteAddr); err != nil {
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
	userInfo, err := h.oauthProvider.Exchange(r.Context(), code, attempt.CodeVerifier, attempt.Nonce)
	if err != nil {
		log.Printf("oauth exchange error: %v", err)
		http.Error(w, `{"error":"oauth exchange failed"}`, http.StatusBadRequest)
		return
	}
	user, ok := h.linkWorkOSUser(w, userInfo)
	if !ok {
		return
	}
	if _, err := h.createSessionForUser(w, r, user); err != nil {
		log.Printf("create session failed: %v", err)
		http.Error(w, `{"error":"cannot create session"}`, http.StatusInternalServerError)
		return
	}
	redirectTo := strings.TrimRight(h.appBaseURL, "/")
	if redirectTo == "" {
		redirectTo = "/"
	}
	http.Redirect(w, r, redirectTo, http.StatusFound)
}

// ExchangeWorkOS handles native (Flutter) AuthKit PKCE completion.
// The mobile app opens AuthKit with a custom-scheme redirect, then posts code+verifier here.
func (h *Handler) ExchangeWorkOS(w http.ResponseWriter, r *http.Request) {
	if h.oauthProvider == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "oauth not configured"})
		return
	}
	var body struct {
		Code         string `json:"code"`
		CodeVerifier string `json:"code_verifier"`
		RedirectURI  string `json:"redirect_uri"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Code == "" || body.CodeVerifier == "" {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if body.RedirectURI != auth.NativeAuthRedirectURI {
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
	sessionToken, err := h.createSessionForUser(w, r, user)
	if err != nil {
		log.Printf("create session failed: %v", err)
		http.Error(w, `{"error":"cannot create session"}`, http.StatusInternalServerError)
		return
	}
	payload := h.sessionPayload(user)
	payload["session_token"] = sessionToken
	writeJSON(w, http.StatusOK, payload)
}

// --- Entry handlers ---

func (h *Handler) ListEntries(w http.ResponseWriter, r *http.Request) {
	userID := getUserID(r)
	subjectID, err := h.calendarSubject(userID)
	if err != nil {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "share inactive"})
		return
	}
	year, month := parseYearMonth(r)
	if year == 0 {
		now := time.Now().UTC()
		year, month = now.Year(), int(now.Month())
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
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "share inactive"})
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
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "share inactive"})
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
	// Allow enabling without a web-push subscription so native clients can
	// schedule OS local notifications. Deliverable still reflects push readiness.
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
