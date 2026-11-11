package handler

import (
	"log"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"217/backend/internal/passwordauth"
)

// ipKey is the per-IP lockout/rate key for this request. It folds IPv6
// addresses into their /64, so one /64 cannot mint unlimited keys (IPv4 is
// already per-address).
func ipKey(prefix string, r *http.Request) string {
	return clientIPKey(prefix, clientIP(r))
}

// clientIPKey folds an IPv6 address into its /64; other addresses pass through.
func clientIPKey(prefix, ip string) string {
	if parsed := net.ParseIP(strings.TrimSpace(ip)); parsed != nil && parsed.To4() == nil {
		if v6 := parsed.To16(); v6 != nil {
			return prefix + v6[:8].String()
		}
	}
	return prefix + ip
}

// passwordAuthEnabled reports the AUTH_PASSWORD_ENABLED flag (default true).
func (h *Handler) passwordAuthEnabled() bool { return h.passwordEnabled }

// lockoutAllows reports whether the request may proceed; it answers 429
// with Retry-After otherwise.
func (h *Handler) lockoutAllows(w http.ResponseWriter, key string) bool {
	if !h.lockout.Locked(key) {
		return true
	}
	retry := int(h.lockout.RetryAfter().Seconds())
	if retry < 1 {
		retry = 1
	}
	w.Header().Set("Retry-After", strconv.Itoa(retry))
	http.Error(w, `{"error":"too many attempts; try later"}`, http.StatusTooManyRequests)
	return false
}

// accountDelayKey is the per-account throttle key (tarpit, never a lock).
func accountDelayKey(email string) string { return "acct:" + email }

// delaySleep holds a WRONG login attempt for the account's current tarpit
// wait before the caller answers. It honors client cancellation, so a gone
// client stops burning server time (Fail still ran: the count stands).
func (h *Handler) delaySleep(r *http.Request, acctKey string) {
	wait := h.accountDelay.Wait(acctKey)
	if wait <= 0 {
		return
	}
	timer := time.NewTimer(wait)
	defer timer.Stop()
	select {
	case <-timer.C:
	case <-r.Context().Done():
	}
}

// sendVerificationEmail sends the address verification code when mail is on.
// Without SMTP_HOST there is no verification and accounts are accepted at
// once; the code is stored so a later login can require it.
func (h *Handler) sendVerificationEmail(userID, email string) {
	if h.mail == nil {
		return
	}
	code, err := passwordauth.NewVerificationCode()
	if err != nil {
		log.Printf("generating verification code: %v", err)
		return
	}
	if err := h.store.CreateEmailVerification(userID, code, time.Now().UTC().Add(24*time.Hour)); err != nil {
		log.Printf("storing verification code: %v", err)
		return
	}
	if err := h.mail.SendVerification(email, code); err != nil {
		log.Printf("sending verification mail: %v", err)
	}
}
