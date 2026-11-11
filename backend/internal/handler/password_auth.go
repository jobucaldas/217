package handler

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"

	"217/backend/internal/passwordauth"
)

// First-party email+password sign-in. Passwords are Argon2id-hashed; the
// per-IP lockout and password policy live in internal/passwordauth. WorkOS
// stays the default sign-in path; this complements it.

// SignupPassword registers a new account with an email and password. The
// email must be free (never attached to an existing account); verification
// is sent when mail is configured, otherwise the account is usable at once.
func (h *Handler) SignupPassword(w http.ResponseWriter, r *http.Request) {
	if !h.passwordAuthEnabled() {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "password authentication is disabled"})
		return
	}
	if !h.signupLimiter.allow(ipKey("signup:", r)) {
		http.Error(w, `{"error":"rate limited"}`, http.StatusTooManyRequests)
		return
	}
	email, password, ok := h.parseEmailPassword(w, r)
	if !ok {
		return
	}
	if !h.passwordPolicyOK(w, password) {
		return
	}
	// Existing accounts are never attached to from an unauthenticated request.
	if h.emailExists(email) {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "email already registered"})
		return
	}
	user, err := h.store.CreateUser(email, "", "")
	if err != nil {
		log.Printf("signup create user: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	if err := h.setCredentialPassword(user.ID, password); err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	h.sendVerificationEmail(user.ID, email)
	writeJSON(w, http.StatusCreated, map[string]string{"status": "account created"})
}

// LoginPassword signs a user in with email and password (cookie session, or
// Bearer with the device key flow like WorkOS exchange).
func (h *Handler) LoginPassword(w http.ResponseWriter, r *http.Request) {
	if !h.passwordAuthEnabled() {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "password authentication is disabled"})
		return
	}
	email, password, deviceKey, ok := h.parseLoginBody(w, r)
	if !ok {
		return
	}
	ipKey := ipKey("pw:", r)
	acctKey := accountDelayKey(email)
	if !h.lockoutAllows(w, ipKey) {
		return // response already written
	}
	// Enter the per-account gate before any verification, so parallel
	// guesses are serialized and the throttle cannot be raced.
	release, ok := h.accountDelay.Enter(acctKey, r.Context())
	if !ok {
		http.Error(w, `{"error":"too many attempts; try later"}`, http.StatusTooManyRequests)
		return
	}
	defer release()
	userID, verified := h.verifyPassword(email, password)
	if !verified {
		// Wrong attempt: hold the wait it owes before revealing the result.
		h.delaySleep(r, acctKey)
		h.lockout.Fail(ipKey)
		h.accountDelay.Fail(acctKey)
		http.Error(w, `{"error":"invalid email or password"}`, http.StatusUnauthorized)
		return
	}
	user, err := h.store.GetUserByID(userID)
	if err != nil {
		log.Printf("login user lookup: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	// With mail configured the address must be verified before password
	// login works; without SMTP there is no verification at all.
	if h.mail != nil {
		if pending, err := h.store.HasEmailVerification(userID); err == nil && pending {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "verify your email to sign in"})
			return
		}
	}
	h.lockout.Reset(ipKey)
	h.accountDelay.Reset(acctKey)
	h.issueSession(w, r, user, deviceKey)
}

// ChangePassword sets the password for the signed-in account (initial set or
// change; the current password is required once one exists).
func (h *Handler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	var body struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	current, err := h.store.GetPasswordCredential(getUserID(r))
	if err != nil {
		log.Printf("change password lookup: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	if current != "" && !passwordauth.Verify(body.CurrentPassword, current) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "current password is wrong"})
		return
	}
	if !h.passwordPolicyOK(w, body.NewPassword) {
		return
	}
	if err := h.setCredentialPassword(getUserID(r), body.NewPassword); err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// setCredentialPassword hashes and stores the password for userID.
func (h *Handler) setCredentialPassword(userID, password string) error {
	hash, err := passwordauth.Hash(password)
	if err != nil {
		log.Printf("hashing password: %v", err)
		return err
	}
	return h.store.SetPasswordCredential(userID, hash)
}

// RemovePasswordCredential drops the password sign-in method, but only when
// another one remains (the WorkOS identity): a password-only account would
// otherwise be locked out for good.
func (h *Handler) RemovePasswordCredential(w http.ResponseWriter, r *http.Request) {
	if !h.workosLinked(r) {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "set up another sign-in method first",
		})
		return
	}
	if err := h.store.DeletePasswordCredential(getUserID(r)); err != nil {
		log.Printf("remove password credential: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// workosLinked reports whether the signed-in user has a WorkOS identity.
func (h *Handler) workosLinked(r *http.Request) bool {
	subject, err := h.store.WorkOSSubject(getUserID(r))
	return err == nil && subject != ""
}

// parseEmailPassword reads the shared signup/login body shape.
func (h *Handler) parseEmailPassword(w http.ResponseWriter, r *http.Request) (string, string, bool) {
	email, password, _, ok := h.parseLoginBody(w, r)
	return email, password, ok
}

// parseLoginBody decodes email, password and the optional Android device
// public key (same field as the WorkOS exchange).
func (h *Handler) parseLoginBody(w http.ResponseWriter, r *http.Request) (string, string, []byte, bool) {
	var body struct {
		Email    string `json:"email"`
		Password string `json:"password"`
		// Optional: base64 PKIX P-256 key from the Android Keystore, so the
		// app can renew its session later (see device.go).
		DevicePublicKey string `json:"device_public_key"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return "", "", nil, false
	}
	email := strings.ToLower(strings.TrimSpace(body.Email))
	if email == "" || !strings.Contains(email, "@") || len(email) > 254 || body.Password == "" {
		http.Error(w, `{"error":"invalid email or password"}`, http.StatusBadRequest)
		return "", "", nil, false
	}
	var deviceKey []byte
	if body.DevicePublicKey != "" {
		key, err := parseDevicePublicKey(body.DevicePublicKey)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return "", "", nil, false
		}
		deviceKey = key
	}
	return email, body.Password, deviceKey, true
}

// VerifyEmail confirms the address with the code from the verification
// mail; it clears the pending verification so password login works. The
// code is stored only as a hash (store) and compared constant-time; wrong
// codes count against the per-IP lockout. Unknown emails get the same
// response as a wrong code.
func (h *Handler) VerifyEmail(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Email string `json:"email"`
		Code  string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	ipKey := clientIPKey("pwv:", clientIP(r))
	if !h.lockoutAllows(w, ipKey) {
		return
	}
	userID, ok := h.lookupUserIDByEmail(strings.ToLower(strings.TrimSpace(body.Email)))
	if !ok {
		// Unknown email: same response as a wrong code, no information leaked.
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid or expired code"})
		return
	}
	consumed, err := h.store.ConsumeEmailVerification(userID, strings.TrimSpace(body.Code))
	if err != nil {
		log.Printf("consuming verification: %v", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	if !consumed {
		h.lockout.Fail(ipKey)
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid or expired code"})
		return
	}
	h.lockout.Reset(ipKey)
	writeJSON(w, http.StatusOK, map[string]string{"status": "verified"})
}

// ResendVerificationEmail re-sends the verification code for an address;
// rate limited per IP, and the response never says whether the account exists.
func (h *Handler) ResendVerificationEmail(w http.ResponseWriter, r *http.Request) {
	if !h.verifyResendLimiter.allow("resend:" + clientIP(r)) {
		http.Error(w, `{"error":"rate limited"}`, http.StatusTooManyRequests)
		return
	}
	var body struct {
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if userID, ok := h.lookupUserIDByEmail(strings.ToLower(strings.TrimSpace(body.Email))); ok {
		h.sendVerificationEmail(userID, strings.ToLower(strings.TrimSpace(body.Email)))
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "sent"})
}

// emailExists reports whether any account already uses the email.
func (h *Handler) emailExists(email string) bool {
	_, ok := h.lookupUserIDByEmail(email)
	return ok
}

// lookupUserIDByEmail resolves a sign-in email to its user ID ("" when unknown).
func (h *Handler) lookupUserIDByEmail(email string) (string, bool) {
	user, err := h.store.GetUserByEmail(email)
	if err != nil || user == nil {
		return "", false
	}
	return user.ID, true
}

// verifyPassword checks the credentials for email. Unknown emails and wrong
// passwords both burn a dummy hash so timing does not distinguish them.
func (h *Handler) verifyPassword(email, password string) (string, bool) {
	userID, hash, err := h.store.LookupPasswordHashByEmail(email)
	if err != nil || hash == "" {
		passwordauth.DummyVerify()
		return "", false
	}
	if !passwordauth.Verify(password, hash) {
		return "", false
	}
	return userID, true
}

// passwordPolicyOK answers 400 when password is not acceptable.
func (h *Handler) passwordPolicyOK(w http.ResponseWriter, password string) bool {
	if !passwordauth.ValidPassword(password) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "password must be 15-128 characters",
		})
		return false
	}
	return true
}
