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
// pages offer to download, withdraw or delete (reported as recent_sign_in).
const defaultReauthWindow = 5 * time.Minute

// SetReauthWindow sets how recent a sign-in counts as recent_sign_in.
func (h *Handler) SetReauthWindow(d time.Duration) { h.reauthWindow = d }

func (h *Handler) sessionIsFresh(token string) bool {
	created, err := h.store.SessionCreatedAt(token)
	return err == nil && time.Since(created) < h.reauthWindow
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
	http.Redirect(w, r, target, http.StatusMovedPermanently)
}

// safeReturnPath keeps only the web app's privacy pages (never another
// host), so the sign-in callback cannot be turned into an open redirect.
func safeReturnPath(path string) string {
	if strings.ContainsAny(path, "\\\r\n#") || strings.Contains(path, "//") {
		return ""
	}
	for _, page := range []string{privacyAppPath, accountDeleteAppPath} {
		if path == page || strings.HasPrefix(path, page+"?") {
			return path
		}
	}
	return ""
}
