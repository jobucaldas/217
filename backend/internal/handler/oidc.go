package handler

import (
	"encoding/json"
	"errors"

	"217/backend/internal/auth"
	"217/backend/internal/store"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const oidcCallbackPath = "/api/auth/oidc/callback"
const oidcAppURL = "com.caldasstudios.app217://oidc"
const oidcCodeBinding = "217-oidc-native-code"
const oidcLinkBinding = "217-oidc-link-token"

type oidcAttempt struct{ Kind, Verifier, Challenge, UserID, Platform, Return string }

func (h *Handler) oidcGone(w http.ResponseWriter) bool {
	if h.oidc.Enabled() {
		return false
	}
	writeJSON(w, http.StatusGone, map[string]string{"error": "oidc disabled"})
	return true
}

func (h *Handler) OIDCEnabled(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !h.oidcGone(w) {
			next(w, r)
		}
	}
}

func (h *Handler) oidcStart(w http.ResponseWriter, r *http.Request, a oidcAttempt) (string, bool) {
	if !h.authLimiter.allow("oidc:" + clientIP(r)) {
		http.Error(w, `{"error":"rate limited"}`, 429)
		return "", false
	}
	state, err := generateRandom(32)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, 500)
		return "", false
	}
	verifier, err := generateRandom(32)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, 500)
		return "", false
	}
	nonce, err := generateRandom(32)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, 500)
		return "", false
	}
	binding, err := generateRandom(32)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, 500)
		return "", false
	}
	redirect := h.requestOrigin(r) + oidcCallbackPath
	authURL, err := h.oidc.AuthURL(r.Context(), redirect, state, pkceChallengeS256(verifier), nonce, a.Return != "" || a.Kind == "link")
	if err != nil {
		http.Error(w, `{"error":"oidc unavailable"}`, 503)
		return "", false
	}
	a.Verifier = verifier
	payload, err := json.Marshal(a)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, 500)
		return "", false
	}
	expires := time.Now().UTC().Add(2 * time.Minute)
	if err := h.store.CreateOAuthAttempt(state, binding, string(payload), nonce, redirect, expires); err != nil {
		http.Error(w, `{"error":"internal error"}`, 500)
		return "", false
	}
	cookie := h.oauthBindingCookieValue(binding, expires)
	cookie.Path = oidcCallbackPath
	http.SetCookie(w, cookie)
	w.Header().Set("Cache-Control", "no-store")
	return authURL, true
}

func (h *Handler) StartOIDC(w http.ResponseWriter, r *http.Request) {
	if h.oidcGone(w) {
		return
	}
	u, ok := h.oidcStart(w, r, oidcAttempt{Kind: "web", Return: safeReturnPath(r.URL.Query().Get("return"))})
	if ok {
		writeJSON(w, 200, map[string]string{"auth_url": u})
	}
}
func (h *Handler) StartOIDCNative(w http.ResponseWriter, r *http.Request) {
	if h.oidcGone(w) {
		return
	}
	challenge := r.URL.Query().Get("app_challenge")
	if len(challenge) != 43 {
		http.Error(w, `{"error":"invalid challenge"}`, 400)
		return
	}
	u, ok := h.oidcStart(w, r, oidcAttempt{Kind: "native", Challenge: challenge})
	if ok {
		http.Redirect(w, r, u, 302)
	}
}
func oidcFailure(w http.ResponseWriter, r *http.Request, a oidcAttempt, redirectURI, reason string) {
	target := strings.TrimSuffix(redirectURI, oidcCallbackPath) + "/app/?auth_error=" + reason
	if a.Kind == "native" {
		target = oidcAppURL + "?error=" + reason
	} else if a.Kind == "link" {
		target = strings.TrimSuffix(redirectURI, oidcCallbackPath) + "/app/?link_error=oidc"
		if a.Platform == "android" {
			target = oidcAppURL + "?link_error=oidc"
		}
	}
	http.Redirect(w, r, target, http.StatusFound)
}

func (h *Handler) OIDCCallback(w http.ResponseWriter, r *http.Request) {
	if h.oidcGone(w) {
		return
	}
	cookie, err := r.Cookie(oauthBindingCookie)
	if err != nil {
		http.Error(w, `{"error":"invalid state"}`, 400)
		return
	}
	clear := h.clearOAuthBindingCookie()
	clear.Path = oidcCallbackPath
	http.SetCookie(w, clear)
	attempt, err := h.store.ConsumeOAuthAttempt(r.URL.Query().Get("state"), cookie.Value)
	if err != nil {
		http.Error(w, `{"error":"invalid state"}`, 400)
		return
	}
	var a oidcAttempt
	if json.Unmarshal([]byte(attempt.CodeVerifier), &a) != nil {
		http.Error(w, `{"error":"invalid state"}`, 400)
		return
	}
	if a.Kind != "web" && a.Kind != "native" && a.Kind != "link" {
		http.Error(w, `{"error":"invalid state"}`, 400)
		return
	}
	if r.URL.Query().Get("error") != "" || r.URL.Query().Get("code") == "" {
		oidcFailure(w, r, a, attempt.RedirectURI, "oidc_failed")
		return
	}
	info, err := h.oidc.Exchange(r.Context(), attempt.RedirectURI, r.URL.Query().Get("code"), a.Verifier, attempt.Nonce)
	if err != nil {
		if errors.Is(err, auth.ErrOIDCUnavailable) {
			http.Error(w, `{"error":"oidc unavailable"}`, 503)
		} else {
			oidcFailure(w, r, a, attempt.RedirectURI, "oidc_failed")
		}
		return
	}
	if a.Kind == "link" {
		err = h.store.AttachOIDCIdentity(a.UserID, h.oidc.Issuer, info.Subject)
		target := strings.TrimSuffix(attempt.RedirectURI, oidcCallbackPath) + "/app/?linked=oidc"
		if a.Platform == "android" {
			target = oidcAppURL + "?linked=1"
		}
		if err != nil {
			target = strings.TrimSuffix(attempt.RedirectURI, oidcCallbackPath) + "/app/?link_error=oidc"
			if a.Platform == "android" {
				target = oidcAppURL + "?link_error=oidc"
			}
		}
		http.Redirect(w, r, target, 302)
		return
	}
	user, err := h.store.LinkOIDCIdentity(h.oidc.Issuer, info.Subject, info.Email, info.Name, info.EmailVerified)
	if err != nil {
		reason := "oidc_failed"
		if errors.Is(err, store.ErrOIDCAccountExists) {
			reason = "account_exists"
		}
		oidcFailure(w, r, a, attempt.RedirectURI, reason)
		return
	}
	if a.Kind == "native" {
		code, err := generateRandom(32)
		if err != nil {
			oidcFailure(w, r, a, attempt.RedirectURI, "oidc_failed")
			return
		}
		if err = h.store.CreateOAuthAttempt(code, oidcCodeBinding, user.ID, a.Challenge, "", time.Now().Add(2*time.Minute)); err != nil {
			oidcFailure(w, r, a, attempt.RedirectURI, "oidc_failed")
			return
		}
		http.Redirect(w, r, oidcAppURL+"?code="+url.QueryEscape(code), 302)
		return
	}
	if _, err = h.createSessionForUser(w, r, user, ""); err != nil {
		oidcFailure(w, r, a, attempt.RedirectURI, "oidc_failed")
		return
	}
	target := strings.TrimSuffix(attempt.RedirectURI, oidcCallbackPath)
	if a.Return != "" {
		target += safeReturnPath(a.Return)
	} else {
		target += "/app/"
	}
	http.Redirect(w, r, target, 302)
}
func (h *Handler) ExchangeOIDC(w http.ResponseWriter, r *http.Request) {
	if h.oidcGone(w) {
		return
	}
	var b struct {
		Code      string `json:"code"`
		Verifier  string `json:"code_verifier"`
		DeviceKey string `json:"device_public_key"`
	}
	if json.NewDecoder(r.Body).Decode(&b) != nil || b.Code == "" {
		http.Error(w, `{"error":"invalid request"}`, 400)
		return
	}
	attempt, err := h.store.ConsumeOAuthAttempt(b.Code, oidcCodeBinding)
	if err != nil || b.Verifier == "" || pkceChallengeS256(b.Verifier) != attempt.Nonce {
		http.Error(w, `{"error":"invalid code"}`, 400)
		return
	}
	var key []byte
	if b.DeviceKey != "" {
		key, err = parseDevicePublicKey(b.DeviceKey)
		if err != nil {
			http.Error(w, `{"error":"invalid device key"}`, 400)
			return
		}
	}
	u, err := h.store.GetUserByID(attempt.CodeVerifier)
	if err != nil {
		http.Error(w, `{"error":"invalid code"}`, 400)
		return
	}
	h.issueSession(w, r, u, key)
}
func (h *Handler) BeginOIDCLink(w http.ResponseWriter, r *http.Request) {
	if h.oidcGone(w) {
		return
	}
	var b struct {
		Platform string `json:"platform"`
	}
	if json.NewDecoder(r.Body).Decode(&b) != nil || (b.Platform != "web" && b.Platform != "android") {
		http.Error(w, `{"error":"invalid platform"}`, 400)
		return
	}
	token, err := generateRandom(32)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, 500)
		return
	}
	if h.store.CreateOAuthAttempt(token, oidcLinkBinding, getUserID(r), b.Platform, "", time.Now().Add(2*time.Minute)) != nil {
		http.Error(w, `{"error":"internal error"}`, 500)
		return
	}
	writeJSON(w, 200, map[string]string{"url": h.requestOrigin(r) + "/api/auth/oidc/link?token=" + url.QueryEscape(token)})
}
func (h *Handler) StartOIDCLink(w http.ResponseWriter, r *http.Request) {
	if h.oidcGone(w) {
		return
	}
	a, err := h.store.ConsumeOAuthAttempt(r.URL.Query().Get("token"), oidcLinkBinding)
	if err != nil {
		http.Error(w, `{"error":"invalid token"}`, 400)
		return
	}
	u, ok := h.oidcStart(w, r, oidcAttempt{Kind: "link", UserID: a.CodeVerifier, Platform: a.Nonce})
	if ok {
		http.Redirect(w, r, u, 302)
	}
}
func (h *Handler) DeleteOIDC(w http.ResponseWriter, r *http.Request) {
	if h.oidcGone(w) {
		return
	}
	err := h.store.RemoveSignInMethod(getUserID(r), h.oidc.Issuer, false, h.passwordAuthEnabled(), !h.workosDisabled && h.authkitEnabled())
	if errors.Is(err, store.ErrOnlySignInMethod) {
		writeJSON(w, 409, map[string]string{"error": "set up another sign-in method first"})
		return
	}
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, 500)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
