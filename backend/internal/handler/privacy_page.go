package handler

import (
	"context"
	"crypto/subtle"
	"html/template"
	"log"
	"net/http"
	"net/mail"
	"net/url"
	"strings"
	"time"

	"217/backend/internal/auth"
	"217/backend/internal/model"
)

// privacyPagePath serves the privacy notice and the privacy actions (download,
// delete, withdraw consent) as a plain web page, so the app only links to it.
const privacyPagePath = "/api/privacy"

// defaultReauthWindow is how recent a sign-in must be to download the data.
const defaultReauthWindow = 5 * time.Minute

// SetReauthWindow sets how recent a sign-in must be before the privacy page
// hands out the data export.
func (h *Handler) SetReauthWindow(d time.Duration) { h.reauthWindow = d }

type privacyView struct {
	Lang       string
	T          privacyText
	Langs      []privacyLangLink
	Server     string
	Contact    string
	ContactURL string
	Nonce      string

	AuthKit      bool
	SignedIn     bool
	Email        string
	HasConsent   bool
	Fresh        bool
	CSRF         string
	DeleteWarn   string
	Confirm      string
	Notice       string
	Error        string
	SignInURL    string
	LoginDeleted bool
}

type privacyLangLink struct {
	Code, Name string
	Current    bool
}

// pageLanguage picks en, pt or es from ?lang=, then Accept-Language, else en.
func pageLanguage(r *http.Request) string {
	if lang := r.URL.Query().Get("lang"); privacyTexts[lang].Title != "" {
		return lang
	}
	if lang := r.PostFormValue("lang"); privacyTexts[lang].Title != "" {
		return lang
	}
	for _, part := range strings.Split(r.Header.Get("Accept-Language"), ",") {
		tag, _, _ := strings.Cut(strings.TrimSpace(part), ";")
		primary, _, _ := strings.Cut(strings.ToLower(tag), "-")
		if privacyTexts[primary].Title != "" {
			return primary
		}
	}
	return "en"
}

func privacyPageURL(lang string, extra ...string) string {
	q := url.Values{"lang": {lang}}
	for i := 0; i+1 < len(extra); i += 2 {
		q.Set(extra[i], extra[i+1])
	}
	return privacyPagePath + "?" + q.Encode()
}

// privacyCSRF ties the page's forms to the session cookie; another site can
// neither read the cookie nor the page, so it cannot forge the token.
func privacyCSRF(sessionToken string) string {
	return hashHex("217-privacy-form:" + sessionToken)
}

// privacySession resolves the cookie session of a privacy page request.
func (h *Handler) privacySession(w http.ResponseWriter, r *http.Request) (*model.User, string) {
	cookie, err := r.Cookie(h.sessionCookie)
	if err != nil || cookie.Value == "" {
		return nil, ""
	}
	user, err := h.store.GetUserBySession(cookie.Value)
	if err != nil {
		http.SetCookie(w, h.clearSessionCookie())
		return nil, ""
	}
	return user, cookie.Value
}

func (h *Handler) sessionIsFresh(token string) bool {
	created, err := h.store.SessionCreatedAt(token)
	return err == nil && time.Since(created) < h.reauthWindow
}

// PrivacyPage renders the notice and, for a signed-in browser, the actions.
func (h *Handler) PrivacyPage(w http.ResponseWriter, r *http.Request) {
	h.renderPrivacy(w, r, http.StatusOK, "")
}

func (h *Handler) renderPrivacy(w http.ResponseWriter, r *http.Request, status int, errMsg string) {
	lang := pageLanguage(r)
	t := privacyTexts[lang]
	nonce, err := generateRandom(18)
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	v := privacyView{
		Lang:      lang,
		T:         t,
		Server:    h.privacyServerLabel(r),
		Nonce:     nonce,
		AuthKit:   h.authkitEnabled(),
		Error:     errMsg,
		SignInURL: privacyPagePath + "/signin?" + url.Values{"lang": {lang}}.Encode(),
	}
	for _, code := range []string{"en", "pt", "es"} {
		v.Langs = append(v.Langs, privacyLangLink{Code: code, Name: privacyTexts[code].LangName, Current: code == lang})
	}
	v.Contact, v.ContactURL = privacyContactLink(h.privacyContact)
	_, v.LoginDeleted = h.oauthProvider.(auth.WorkOSUserDeleter)
	if c, ok := h.oauthProvider.(auth.UserDeleteConfigurer); ok && !c.CanDeleteUsers() {
		v.LoginDeleted = false
	}
	v.DeleteWarn = t.DeleteWarnKeepsLogin
	if v.LoginDeleted {
		v.DeleteWarn = t.DeleteWarnDeletesLogin
	}
	switch r.URL.Query().Get("done") {
	case "deleted":
		v.Notice = t.DoneDeleted
	case "withdrawn":
		v.Notice = t.DoneWithdrawn
	}
	if user, token := h.privacySession(w, r); user != nil {
		v.SignedIn = true
		v.Email = user.Email
		v.HasConsent = user.HasConsent()
		v.Fresh = h.sessionIsFresh(token)
		v.CSRF = privacyCSRF(token)
		switch confirm := r.URL.Query().Get("confirm"); confirm {
		case "delete":
			v.Confirm = confirm
		case "withdraw":
			if v.HasConsent {
				v.Confirm = confirm
			}
		}
	}

	hdr := w.Header()
	hdr.Set("Content-Type", "text/html; charset=utf-8")
	hdr.Set("Cache-Control", "no-store")
	hdr.Set("Content-Security-Policy", "default-src 'none'; style-src 'nonce-"+nonce+"'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
	// Same-origin form posts must carry their Origin (no-referrer sends "null").
	hdr.Set("Referrer-Policy", "same-origin")
	hdr.Set("Content-Language", lang)
	w.WriteHeader(status)
	if err := privacyTemplate.Execute(w, v); err != nil {
		log.Printf("privacy page: %v", err)
	}
}

// privacyServerLabel is the host people are on, as named in the notice.
func (h *Handler) privacyServerLabel(r *http.Request) string {
	if u, err := url.Parse(h.requestOrigin(r)); err == nil && u.Host != "" {
		return u.Host
	}
	if r.Host != "" {
		return r.Host
	}
	return "217"
}

// privacyContactLink turns PRIVACY_CONTACT into display text and a link
// (mailto: for an email, the URL itself for http(s)); "" when unset.
func privacyContactLink(contact string) (string, string) {
	if contact == "" {
		return "", ""
	}
	if addr, err := mail.ParseAddress(contact); err == nil && !strings.Contains(contact, "://") {
		return contact, "mailto:" + addr.Address
	}
	if u, err := url.Parse(contact); err == nil && (u.Scheme == "https" || u.Scheme == "http") && u.Host != "" {
		return contact, u.String()
	}
	return contact, ""
}

// PrivacySignIn starts a browser AuthKit sign-in that lands back on the page.
// AuthKit always asks for credentials again (max_age=0), so it also serves
// as the re-authentication before a download.
func (h *Handler) PrivacySignIn(w http.ResponseWriter, r *http.Request) {
	lang := pageLanguage(r)
	authURL, status, _ := h.beginBrowserOAuth(w, r, privacyPageURL(lang))
	if authURL == "" {
		h.renderPrivacy(w, r, status, privacyTexts[lang].SignInFailed)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	http.Redirect(w, r, authURL, http.StatusSeeOther)
}

// privacyFormUser checks a privacy page form post: a live cookie session, the
// form's CSRF token and, when sent, an allowed Origin.
func (h *Handler) privacyFormUser(w http.ResponseWriter, r *http.Request) (*model.User, string, bool) {
	t := privacyTexts[pageLanguage(r)]
	if origin := r.Header.Get("Origin"); origin != "" && origin != "null" && !h.sameOriginAllowed(r) {
		h.renderPrivacy(w, r, http.StatusForbidden, t.FormExpired)
		return nil, "", false
	}
	user, token := h.privacySession(w, r)
	if user == nil {
		h.renderPrivacy(w, r, http.StatusUnauthorized, t.SignedOutError)
		return nil, "", false
	}
	sent := r.PostFormValue("csrf")
	if subtle.ConstantTimeCompare([]byte(sent), []byte(privacyCSRF(token))) != 1 {
		h.renderPrivacy(w, r, http.StatusForbidden, t.FormExpired)
		return nil, "", false
	}
	return user, token, true
}

// PrivacyExport downloads the data export, but only shortly after a sign-in;
// otherwise it sends the browser through AuthKit first.
func (h *Handler) PrivacyExport(w http.ResponseWriter, r *http.Request) {
	user, token, ok := h.privacyFormUser(w, r)
	if !ok {
		return
	}
	if !h.sessionIsFresh(token) {
		http.Redirect(w, r, privacyPagePath+"/signin?"+url.Values{"lang": {pageLanguage(r)}}.Encode(), http.StatusSeeOther)
		return
	}
	h.ExportAccount(w, r.WithContext(context.WithValue(r.Context(), userIDKey, user.ID)))
}

// PrivacyDelete erases the account after the page's confirmation step.
func (h *Handler) PrivacyDelete(w http.ResponseWriter, r *http.Request) {
	user, _, ok := h.privacyFormUser(w, r)
	if !ok {
		return
	}
	lang := pageLanguage(r)
	if status, _ := h.deleteAccount(r.Context(), user.ID); status != 0 {
		h.renderPrivacy(w, r, status, privacyTexts[lang].DeleteFailed)
		return
	}
	http.SetCookie(w, h.clearSessionCookie())
	http.Redirect(w, r, privacyPageURL(lang, "done", "deleted"), http.StatusSeeOther)
}

// PrivacyWithdraw revokes consent after the page's confirmation step.
func (h *Handler) PrivacyWithdraw(w http.ResponseWriter, r *http.Request) {
	user, _, ok := h.privacyFormUser(w, r)
	if !ok {
		return
	}
	lang := pageLanguage(r)
	if _, err := h.store.RecordConsent(user.ID, 0); err != nil {
		log.Printf("withdraw consent: %v", err)
		h.renderPrivacy(w, r, http.StatusInternalServerError, privacyTexts[lang].WithdrawFailed)
		return
	}
	http.Redirect(w, r, privacyPageURL(lang, "done", "withdrawn"), http.StatusSeeOther)
}

var privacyTemplate = template.Must(template.New("privacy").Parse(`<!doctype html>
<html lang="{{.Lang}}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="same-origin">
<meta name="color-scheme" content="light dark">
<title>{{.T.Title}} · 217</title>
<style nonce="{{.Nonce}}">
:root{--bg:#f6f7fb;--card:#fff;--text:#111827;--muted:#4b5563;--line:#e5e7eb;--accent:#2563eb;--on-accent:#fff;--hl:#fdf2f8;--on-hl:#831843;--danger:#dc2626;--warn:#b45309;--ok:#047857}
@media (prefers-color-scheme:dark){:root{--bg:#0b0d12;--card:#161a22;--text:#f3f4f6;--muted:#a1a7b3;--line:#2a303c;--accent:#60a5fa;--on-accent:#0b1220;--hl:#3b0d24;--on-hl:#fbcfe8;--danger:#f87171;--warn:#fbbf24;--ok:#34d399}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:680px;margin:0 auto;padding:20px 16px 48px}
header{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:8px;margin-bottom:8px}
.brand{font-weight:700;font-size:18px}
nav a{color:var(--muted);margin-left:10px;text-decoration:none;padding:6px 2px}
nav a[aria-current]{color:var(--text);font-weight:600;text-decoration:underline}
h1{font-size:28px;line-height:1.2;margin:12px 0 4px}
h2{font-size:18px;margin:0 0 4px}
p{margin:0;color:var(--muted)}
section{margin-top:20px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px;margin-top:12px}
.hl{background:var(--hl);border-color:transparent}.hl h2,.hl p{color:var(--on-hl)}
.status{border-left:4px solid var(--ok)}.error{border-left:4px solid var(--danger)}
.danger-card{border-color:var(--danger)}
.btn{display:inline-flex;align-items:center;justify-content:center;min-height:48px;padding:10px 18px;border-radius:999px;border:1px solid var(--line);background:transparent;color:var(--text);font:inherit;font-weight:600;text-decoration:none;cursor:pointer;width:100%;margin-top:12px}
.btn.primary{background:var(--accent);border-color:var(--accent);color:var(--on-accent)}
.btn.danger{background:var(--danger);border-color:var(--danger);color:#fff}
.btn.warn{border-color:var(--warn);color:var(--warn)}
.btn.danger-outline{border-color:var(--danger);color:var(--danger)}
.btn:focus-visible,a:focus-visible{outline:3px solid var(--accent);outline-offset:2px}
.row{display:flex;gap:10px;flex-wrap:wrap}.row>*{flex:1 1 180px}
a{color:var(--accent)}
form{margin:0}
small{display:block;color:var(--muted);margin-top:8px}
</style>
</head>
<body>
<main>
<header>
<span class="brand">217</span>
<nav aria-label="{{.T.LanguageLabel}}">{{range .Langs}}<a href="?lang={{.Code}}" lang="{{.Code}}" hreflang="{{.Code}}"{{if .Current}} aria-current="true"{{end}}>{{.Name}}</a>{{end}}</nav>
</header>
<h1>{{.T.Title}}</h1>
<p>{{.T.Intro}}</p>
{{if .Notice}}<div class="card status" role="status"><p>{{.Notice}}</p></div>{{end}}
{{if .Error}}<div class="card error" role="alert"><p>{{.Error}}</p></div>{{end}}

{{if eq .Confirm "delete"}}
<section aria-labelledby="confirm-title" class="card danger-card">
<h2 id="confirm-title">{{.T.DeleteConfirmTitle}}</h2>
<p>{{.DeleteWarn}}</p>
<form method="post" action="/api/privacy/delete">
<input type="hidden" name="csrf" value="{{.CSRF}}"><input type="hidden" name="lang" value="{{.Lang}}">
<div class="row"><a class="btn" href="?lang={{.Lang}}">{{.T.Cancel}}</a><button class="btn danger" type="submit">{{.T.DeleteConfirm}}</button></div>
</form>
</section>
{{else if eq .Confirm "withdraw"}}
<section aria-labelledby="confirm-title" class="card danger-card">
<h2 id="confirm-title">{{.T.WithdrawConfirmTitle}}</h2>
<p>{{.T.WithdrawWarn}}</p>
<form method="post" action="/api/privacy/withdraw">
<input type="hidden" name="csrf" value="{{.CSRF}}"><input type="hidden" name="lang" value="{{.Lang}}">
<div class="row"><a class="btn" href="?lang={{.Lang}}">{{.T.Cancel}}</a><button class="btn danger" type="submit">{{.T.WithdrawConfirm}}</button></div>
</form>
</section>
{{end}}

<section class="card hl" aria-labelledby="s-sensitive"><h2 id="s-sensitive">{{.T.SensitiveTitle}}</h2><p>{{.T.SensitiveBody}}</p></section>
<section aria-labelledby="s-what"><h2 id="s-what">{{.T.WhatTitle}}</h2><p>{{.T.WhatBody}}</p></section>
<section aria-labelledby="s-why"><h2 id="s-why">{{.T.WhyTitle}}</h2><p>{{.T.WhyBody}}</p></section>
<section aria-labelledby="s-where"><h2 id="s-where">{{.T.WhereTitle}}</h2><p>{{printf .T.WhereBody .Server}}</p></section>
<section aria-labelledby="s-rights"><h2 id="s-rights">{{.T.RightsTitle}}</h2><p>{{.T.RightsBody}}</p></section>
<section aria-labelledby="s-contact"><h2 id="s-contact">{{.T.ContactTitle}}</h2><p>{{if .ContactURL}}<a href="{{.ContactURL}}">{{.Contact}}</a>{{else if .Contact}}{{.Contact}}{{else}}{{.T.ContactNone}}{{end}}</p></section>

<section id="your-data" aria-labelledby="s-data">
<h2 id="s-data">{{.T.YourDataTitle}}</h2>
{{if .SignedIn}}
<p>{{printf .T.SignedInAs .Email}}{{if not .HasConsent}} {{.T.NoConsent}}{{end}}</p>
<div class="card">
<h2>{{.T.DownloadTitle}}</h2>
<p>{{.T.DownloadBody}}</p>
{{if .Fresh}}
<form method="post" action="/api/privacy/export">
<input type="hidden" name="csrf" value="{{.CSRF}}"><input type="hidden" name="lang" value="{{.Lang}}">
<button class="btn primary" type="submit">{{.T.DownloadAction}}</button>
</form>
<small>{{.T.DownloadFresh}}</small>
{{else}}
<a class="btn primary" href="{{.SignInURL}}">{{.T.DownloadReauth}}</a>
<small>{{.T.DownloadReauthNote}}</small>
{{end}}
</div>
{{if .HasConsent}}
<div class="card">
<h2>{{.T.WithdrawTitle}}</h2>
<p>{{.T.WithdrawBody}}</p>
<a class="btn warn" href="?lang={{.Lang}}&amp;confirm=withdraw#confirm-title">{{.T.WithdrawAction}}</a>
</div>
{{end}}
<div class="card">
<h2>{{.T.DeleteTitle}}</h2>
<p>{{.T.DeleteBody}}</p>
<a class="btn danger-outline" href="?lang={{.Lang}}&amp;confirm=delete#confirm-title">{{.T.DeleteAction}}</a>
</div>
{{else if .AuthKit}}
<p>{{.T.SignInPrompt}}</p>
<a class="btn primary" href="{{.SignInURL}}">{{.T.SignInAction}}</a>
{{else}}
<p>{{.T.SignInUnavailable}}</p>
{{end}}
</section>
</main>
</body>
</html>
`))
