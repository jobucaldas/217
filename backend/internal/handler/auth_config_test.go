package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"217/backend/internal/store"
)

func TestAuthConfigPasswordAlwaysDisabled(t *testing.T) {
	h := New(store.NewMemoryStore())
	req := httptest.NewRequest(http.MethodGet, "/api/auth/config", nil)
	w := httptest.NewRecorder()
	h.AuthConfig(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status %d", w.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["password"] != false {
		t.Fatalf("password = %#v", body["password"])
	}
	if body["authkit"] != false {
		t.Fatalf("authkit without provider = %#v", body["authkit"])
	}
}

func TestPasswordLoginForbidden(t *testing.T) {
	h := New(store.NewMemoryStore())
	req := httptest.NewRequest(http.MethodPost, "/api/auth/login", strings.NewReader(`{"email":"a@b.c","password":"x"}`))
	w := httptest.NewRecorder()
	h.Login(w, req)
	if w.Code != http.StatusForbidden {
		t.Fatalf("status %d body %s", w.Code, w.Body.String())
	}
}

func TestLoginRateLimited(t *testing.T) {
	h := New(store.NewMemoryStore())
	h.SetRateLimit(2)
	for i := 0; i < 2; i++ {
		req := httptest.NewRequest(http.MethodPost, "/api/auth/login", strings.NewReader(`{}`))
		req.RemoteAddr = "203.0.113.9:1234"
		w := httptest.NewRecorder()
		h.Login(w, req)
		if w.Code != http.StatusForbidden {
			t.Fatalf("attempt %d status %d", i, w.Code)
		}
	}
	req := httptest.NewRequest(http.MethodPost, "/api/auth/login", strings.NewReader(`{}`))
	req.RemoteAddr = "203.0.113.9:1234"
	w := httptest.NewRecorder()
	h.Login(w, req)
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", w.Code)
	}
}
