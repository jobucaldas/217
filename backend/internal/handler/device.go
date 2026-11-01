package handler

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"time"
)

// Device keys let the Android app stay signed in: at sign-in it registers the
// public half of a P-256 key kept in the Android Keystore, and when its
// session runs out it signs a one-time challenge to get a new one.

const deviceChallengeTTL = 2 * time.Minute

// deviceSignedMessage is what the device signs (SHA256withECDSA).
func deviceSignedMessage(keyID, challenge string) []byte {
	return []byte("217 device session v1\n" + keyID + "\n" + challenge)
}

// parseDevicePublicKey accepts a base64 PKIX (SubjectPublicKeyInfo) P-256
// key and returns its DER bytes.
func parseDevicePublicKey(encoded string) ([]byte, error) {
	der, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, errors.New("device public key is not base64")
	}
	pub, err := x509.ParsePKIXPublicKey(der)
	if err != nil {
		return nil, errors.New("device public key is not PKIX")
	}
	ec, ok := pub.(*ecdsa.PublicKey)
	if !ok || ec.Curve != elliptic.P256() {
		return nil, errors.New("device public key must be ECDSA P-256")
	}
	return der, nil
}

func deviceNotRecognized(w http.ResponseWriter) {
	writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "device not recognized"})
}

// DeviceChallenge issues a single-use challenge for a registered device key.
func (h *Handler) DeviceChallenge(w http.ResponseWriter, r *http.Request) {
	if !h.authLimiter.allow("device:" + clientIP(r)) {
		http.Error(w, `{"error":"rate limited"}`, http.StatusTooManyRequests)
		return
	}
	var body struct {
		KeyID string `json:"key_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.KeyID == "" {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	challenge, err := generateRandom(32)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	if err := h.store.SetDeviceChallenge(body.KeyID, challenge, time.Now().UTC().Add(deviceChallengeTTL)); err != nil {
		deviceNotRecognized(w)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, map[string]string{"challenge": challenge})
}

// DeviceSession trades a signed challenge for a new Bearer session.
func (h *Handler) DeviceSession(w http.ResponseWriter, r *http.Request) {
	if !h.authLimiter.allow("device:" + clientIP(r)) {
		http.Error(w, `{"error":"rate limited"}`, http.StatusTooManyRequests)
		return
	}
	var body struct {
		KeyID     string `json:"key_id"`
		Challenge string `json:"challenge"`
		Signature string `json:"signature"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.KeyID == "" || body.Challenge == "" || body.Signature == "" {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	sig, err := base64.StdEncoding.DecodeString(body.Signature)
	if err != nil {
		http.Error(w, `{"error":"invalid signature"}`, http.StatusBadRequest)
		return
	}
	// Consumed whatever the outcome: a challenge is good for one try.
	userID, der, err := h.store.ConsumeDeviceChallenge(body.KeyID, body.Challenge)
	if err != nil {
		deviceNotRecognized(w)
		return
	}
	pub, err := x509.ParsePKIXPublicKey(der)
	ec, ok := pub.(*ecdsa.PublicKey)
	digest := sha256.Sum256(deviceSignedMessage(body.KeyID, body.Challenge))
	if err != nil || !ok || !ecdsa.VerifyASN1(ec, digest[:], sig) {
		deviceNotRecognized(w)
		return
	}
	user, err := h.store.GetUserByID(userID)
	if err != nil {
		deviceNotRecognized(w)
		return
	}
	token, err := h.createSessionForUser(w, r, user, body.KeyID)
	if err != nil {
		log.Printf("create device session failed: %v", err)
		http.Error(w, `{"error":"cannot create session"}`, http.StatusInternalServerError)
		return
	}
	payload := h.sessionPayload(user)
	payload["session_token"] = token
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, payload)
}
