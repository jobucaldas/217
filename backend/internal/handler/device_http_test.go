package handler_test

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"217/backend/internal/auth"
	"217/backend/internal/handler"
)

func postJSON(t *testing.T, fn http.HandlerFunc, path string, body any, bearer string) (int, map[string]any) {
	t.Helper()
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	w := httptest.NewRecorder()
	fn(w, req)
	var resp map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &resp)
	return w.Code, resp
}

func signDevice(t *testing.T, key *ecdsa.PrivateKey, keyID, challenge string) string {
	t.Helper()
	digest := sha256.Sum256([]byte("217 device session v1\n" + keyID + "\n" + challenge))
	sig, err := ecdsa.SignASN1(rand.Reader, key, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(sig)
}

func renewDevice(t *testing.T, h *handler.Handler, key *ecdsa.PrivateKey, keyID string) (int, map[string]any) {
	t.Helper()
	code, resp := postJSON(t, h.DeviceChallenge, "/api/auth/device/challenge", map[string]string{"key_id": keyID}, "")
	if code != http.StatusOK {
		return code, resp
	}
	challenge := resp["challenge"].(string)
	return postJSON(t, h.DeviceSession, "/api/auth/device/session", map[string]string{
		"key_id": keyID, "challenge": challenge, "signature": signDevice(t, key, keyID, challenge),
	}, "")
}

func TestDeviceKeyRenewsSessionUntilLogout(t *testing.T) {
	h, _ := newTestHandler(t)
	h.SetOAuthProvider(&fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{
		Subject: "workos-device-1", Email: "device@example.com", EmailVerified: true, Name: "Device",
	}})
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	der, _ := x509.MarshalPKIXPublicKey(&key.PublicKey)
	code, resp := postJSON(t, h.ExchangeWorkOS, "/api/auth/workos/exchange", map[string]string{
		"code": "auth-code", "code_verifier": "verifier", "redirect_uri": "com.jobucaldas.a217://auth/callback",
		"device_public_key": base64.StdEncoding.EncodeToString(der),
	}, "")
	keyID, _ := resp["device_key_id"].(string)
	if code != http.StatusOK || keyID == "" {
		t.Fatalf("exchange with device key: %d %#v", code, resp)
	}

	code, resp = renewDevice(t, h, key, keyID)
	token, _ := resp["session_token"].(string)
	if code != http.StatusOK || token == "" || resp["user"] == nil {
		t.Fatalf("device renewal: %d %#v", code, resp)
	}

	// A challenge is single use, and only the device's key can answer it.
	_, ch := postJSON(t, h.DeviceChallenge, "/api/auth/device/challenge", map[string]string{"key_id": keyID}, "")
	challenge := ch["challenge"].(string)
	other, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if code, _ := postJSON(t, h.DeviceSession, "/api/auth/device/session", map[string]string{
		"key_id": keyID, "challenge": challenge, "signature": signDevice(t, other, keyID, challenge),
	}, ""); code != http.StatusUnauthorized {
		t.Fatalf("foreign signature accepted: %d", code)
	}
	if code, _ := postJSON(t, h.DeviceSession, "/api/auth/device/session", map[string]string{
		"key_id": keyID, "challenge": challenge, "signature": signDevice(t, key, keyID, challenge),
	}, ""); code != http.StatusUnauthorized {
		t.Fatalf("replayed challenge accepted: %d", code)
	}

	// An expired Bearer session gets 401 at logout, so the app renews first
	// and the key can still be revoked.
	if code, _ := postJSON(t, h.Logout, "/api/auth/logout", map[string]string{}, "expired-token"); code != http.StatusUnauthorized {
		t.Fatalf("logout with unknown bearer: %d", code)
	}

	// Logging out revokes the key: the device has to sign in again.
	if code, _ := postJSON(t, h.Logout, "/api/auth/logout", map[string]string{}, token); code != http.StatusOK {
		t.Fatalf("logout: %d", code)
	}
	if code, _ := renewDevice(t, h, key, keyID); code != http.StatusUnauthorized {
		t.Fatalf("revoked key renewed: %d", code)
	}
}

func TestExchangeRejectsNonP256DeviceKey(t *testing.T) {
	h, _ := newTestHandler(t)
	provider := &fakeOAuthProvider{userInfo: &auth.OAuthUserInfo{
		Subject: "workos-device-2", Email: "device2@example.com", EmailVerified: true,
	}}
	h.SetOAuthProvider(provider)
	key, _ := ecdsa.GenerateKey(elliptic.P384(), rand.Reader)
	der, _ := x509.MarshalPKIXPublicKey(&key.PublicKey)
	code, _ := postJSON(t, h.ExchangeWorkOS, "/api/auth/workos/exchange", map[string]string{
		"code": "auth-code", "code_verifier": "verifier", "redirect_uri": "com.jobucaldas.a217://auth/callback",
		"device_public_key": base64.StdEncoding.EncodeToString(der),
	}, "")
	if code != http.StatusBadRequest || provider.exchangeCode != "" {
		t.Fatalf("P-384 key: %d, exchanged %q", code, provider.exchangeCode)
	}
}
