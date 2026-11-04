package handler

import (
	"net/http"
	"net/url"
	"strings"
	"time"
)

// The privacy notice and the account deletion page are part of the web app
// (served under /app/). The API keeps /api/privacy only as a redirect, for
// app versions that still link there.
const (
	appPath              = "/app/"
	privacyAppPath       = "/app/privacy"
	accountDeleteAppPath = "/app/account/delete"
)

// defaultReauthWindow is how recent a sign-in must be before the privacy
// pages (and the API, for browsers) download, withdraw or delete.
const defaultReauthWindow = 5 * time.Minute

// SetReauthWindow sets how recent a sign-in counts as recent_sign_in.
func (h *Handler) SetReauthWindow(d time.Duration) { h.reauthWindow = d }

func (h *Handler) sessionIsFresh(token string) bool {
	created, err := h.store.SessionCreatedAt(token)
	return err == nil && time.Since(created) < h.reauthWindow
}

// browserSessionIsFresh reports a browser (cookie) session that signed in
// within the reauth window. Bearer sessions never count: the apps renew
// theirs silently with the device key, so their age says nothing about a
// recent sign-in.
func (h *Handler) browserSessionIsFresh(r *http.Request) bool {
	cookie, err := r.Cookie(h.sessionCookie)
	return err == nil && cookie.Value != "" && h.sessionIsFresh(cookie.Value)
}

// RecentBrowserSignIn guards export, consent withdrawal and deletion for
// browsers: a cookie session must have signed in within the reauth window
// (AuthKit always asks for credentials again), else 403 "reauth required".
// The web privacy pages sign in again and return to the same warning. The
// apps (Bearer, behind the device's own lock) are not asked.
func (h *Handler) RecentBrowserSignIn(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if cookie, err := r.Cookie(h.sessionCookie); err == nil && cookie.Value != "" && !h.sessionIsFresh(cookie.Value) {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "reauth required"})
			return
		}
		next(w, r)
	}
}

// pageLanguage keeps only the languages the app speaks.
func pageLanguage(lang string) string {
	switch lang {
	case "en", "pt", "es":
		return lang
	}
	return ""
}

// privacyAction keeps only the page's actions: download, withdraw, delete.
func privacyAction(action string) string {
	switch action {
	case "download", "withdraw", "delete":
		return action
	}
	return ""
}

// LegacyPrivacyPage sends /api/privacy (and its old sign-in link) to the
// web app's privacy page, keeping the language and the open warning step.
func (h *Handler) LegacyPrivacyPage(w http.ResponseWriter, r *http.Request) {
	q := url.Values{}
	if lang := pageLanguage(r.URL.Query().Get("lang")); lang != "" {
		q.Set("lang", lang)
	}
	if action := privacyAction(r.URL.Query().Get("confirm")); action != "" {
		q.Set("confirm", action)
	}
	target := privacyAppPath
	if len(q) > 0 {
		target += "?" + q.Encode()
	}
	http.Redirect(w, r, target, http.StatusFound)
}

// safeReturnPath keeps only the web app's privacy pages (never another
// host), so the sign-in callback cannot be turned into an open redirect. The
// result is rebuilt: the exact page path plus only lang and confirm, each
// limited to its allowed values.
func safeReturnPath(raw string) string {
	if strings.ContainsAny(raw, "\\\r\n#") || strings.Contains(raw, "//") {
		return ""
	}
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "" || u.Host != "" || u.User != nil {
		return ""
	}
	if u.Path != privacyAppPath && u.Path != accountDeleteAppPath {
		return ""
	}
	in := u.Query()
	q := url.Values{}
	if lang := pageLanguage(in.Get("lang")); lang != "" {
		q.Set("lang", lang)
	}
	if action := privacyAction(in.Get("confirm")); action != "" {
		q.Set("confirm", action)
	}
	if len(q) == 0 {
		return u.Path
	}
	return u.Path + "?" + q.Encode()
}
