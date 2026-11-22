package handler

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"217/backend/internal/auth"
	"217/backend/internal/model"
	"217/backend/internal/store"
)

type failingStore struct {
	store.Store
	sessionErr, userErr, shareErr, calendarErr, challengeErr error
	user                                                     *model.User
	key                                                      []byte
	deleteEntryErr, deleteUserErr, messageErr                error
	canEdit                                                  bool
}

func (s *failingStore) GetUserBySession(string) (*model.User, error) { return s.user, s.sessionErr }
func (s *failingStore) GetUserByID(string) (*model.User, error)      { return s.user, s.userErr }
func (s *failingStore) GetShareState(string) (*model.ShareState, error) {
	return &model.ShareState{CanEditCalendar: s.canEdit}, s.shareErr
}
func (s *failingStore) CalendarSubjectID(string) (string, error) { return "", s.calendarErr }
func (s *failingStore) ConsumeDeviceChallenge(string, string) (string, []byte, error) {
	return "user", s.key, s.challengeErr
}

func (s *failingStore) DeleteEntry(string, string) error     { return s.deleteEntryErr }
func (s *failingStore) DeleteUser(string) error              { return s.deleteUserErr }
func (s *failingStore) MarkMessageRead(string, string) error { return s.messageErr }

func TestStoreFailuresDoNotDenyAccess(t *testing.T) {
	failure := errors.New("database unavailable")
	user := &model.User{ID: "user"}
	cases := []struct {
		name            string
		failure, denial error
		wantDenial      int
		run             func(*Handler, http.ResponseWriter, *http.Request)
		set             func(*failingStore, error)
	}{
		{"middleware", failure, store.ErrSessionNotFound, 401, func(h *Handler, w http.ResponseWriter, r *http.Request) {
			h.AuthMiddleware(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(204) })(w, r)
		}, func(s *failingStore, e error) { s.sessionErr = e }},
		{"logout", failure, store.ErrSessionNotFound, 401, (*Handler).Logout, func(s *failingStore, e error) { s.sessionErr = e }},
		{"calendar", failure, store.ErrShareInactive, 403, (*Handler).GetCycle, func(s *failingStore, e error) { s.calendarErr = e }},
		{"edit", failure, nil, 403, (*Handler).UpsertEntry, func(s *failingStore, e error) { s.shareErr = e }},
		{"delete", failure, nil, 403, (*Handler).DeleteEntry, func(s *failingStore, e error) { s.shareErr = e }},
		{"profile", failure, store.ErrUserNotFound, 401, (*Handler).UpdateProfile, func(s *failingStore, e error) { s.userErr = e }},
		{"export", failure, store.ErrUserNotFound, 401, (*Handler).ExportAccount, func(s *failingStore, e error) { s.userErr = e }},
		{"stage", failure, store.ErrUserNotFound, 403, (*Handler).SetStage, func(s *failingStore, e error) { s.userErr = e }},
		{"alerts get", failure, store.ErrUserNotFound, 403, (*Handler).GetPartnerAlerts, func(s *failingStore, e error) { s.userErr = e }},
		{"alerts put", failure, store.ErrUserNotFound, 403, (*Handler).UpsertPartnerAlerts, func(s *failingStore, e error) { s.userErr = e }},
	}
	for _, tc := range cases {
		for _, trial := range []struct {
			name string
			err  error
			want int
		}{{"failure", tc.failure, 503}, {"denial", tc.denial, tc.wantDenial}} {
			t.Run(tc.name+"/"+trial.name, func(t *testing.T) {
				s := &failingStore{Store: store.NewMemoryStore(), user: user}
				tc.set(s, trial.err)
				h := New(s)
				r := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(`{"stage":"cycling"}`))
				r.Header.Set("Authorization", "Bearer token")
				r = r.WithContext(context.WithValue(r.Context(), userIDKey, "user"))
				w := httptest.NewRecorder()
				tc.run(h, w, r)
				if w.Code != trial.want {
					t.Fatalf("status = %d, want %d: %s", w.Code, trial.want, w.Body.String())
				}
			})
		}
	}
}

func TestMiddlewareKeepsCookieOnStoreFailure(t *testing.T) {
	for _, tc := range []struct {
		err     error
		want    int
		cleared bool
	}{
		{errors.New("database unavailable"), 503, false}, {store.ErrSessionNotFound, 401, true},
	} {
		s := &failingStore{Store: store.NewMemoryStore(), sessionErr: tc.err}
		r := httptest.NewRequest(http.MethodGet, "/", nil)
		r.AddCookie(&http.Cookie{Name: "217_session", Value: "token"})
		w := httptest.NewRecorder()
		New(s).AuthMiddleware(func(http.ResponseWriter, *http.Request) {})(w, r)
		if w.Code != tc.want || (len(w.Result().Cookies()) > 0) != tc.cleared {
			t.Fatalf("status %d cookies %v", w.Code, w.Result().Cookies())
		}
	}
}

func TestNotFoundDenialsDistinguishStoreErrors(t *testing.T) {
	for _, tc := range []struct {
		name   string
		denial error
		run    func(*Handler, http.ResponseWriter, *http.Request)
		set    func(*failingStore, error)
	}{
		{"entry", store.ErrEntryNotFound, (*Handler).DeleteEntry, func(s *failingStore, e error) { s.deleteEntryErr = e }},
		{"message", store.ErrMessageNotFound, (*Handler).MarkInboxNoteRead, func(s *failingStore, e error) { s.messageErr = e }},
		{"account", store.ErrUserNotFound, (*Handler).DeleteAccount, func(s *failingStore, e error) { s.deleteUserErr = e }},
	} {
		for _, trial := range []struct {
			err  error
			want int
		}{{errors.New("database not found"), 503}, {tc.denial, 404}} {
			t.Run(tc.name+"/"+trial.err.Error(), func(t *testing.T) {
				s := &failingStore{Store: store.NewMemoryStore(), canEdit: true}
				tc.set(s, trial.err)
				r := httptest.NewRequest(http.MethodDelete, "/", nil)
				r.SetPathValue("date", "2026-01-01")
				r.SetPathValue("id", "id")
				r = r.WithContext(context.WithValue(r.Context(), userIDKey, "user"))
				w := httptest.NewRecorder()
				tc.run(New(s), w, r)
				if w.Code != trial.want {
					t.Fatalf("status = %d, want %d: %s", w.Code, trial.want, w.Body.String())
				}
			})
		}
	}
}

func TestSessionShareFailure(t *testing.T) {
	s := &failingStore{Store: store.NewMemoryStore(), user: &model.User{ID: "user"}, shareErr: errors.New("database unavailable")}
	h := New(s)
	r := httptest.NewRequest(http.MethodGet, "/api/auth/session", nil)
	r.Header.Set("Authorization", "Bearer token")
	w := httptest.NewRecorder()
	h.CurrentSession(w, r)
	if w.Code != 503 {
		t.Fatalf("status = %d, want 503", w.Code)
	}
}

type exchangeFailureProvider struct{}

func (exchangeFailureProvider) AuthCodeURL(string, string, string) string { return "" }
func (exchangeFailureProvider) Exchange(context.Context, string, string, string) (*auth.OAuthUserInfo, error) {
	return &auth.OAuthUserInfo{Subject: "subject", Email: "user@example.com", EmailVerified: true}, nil
}

type trackingFailureStore struct {
	*failingStore
	keys, sessions int
}

func (s *trackingFailureStore) CreateDeviceKey(userID string, key []byte) (string, error) {
	s.keys++
	return s.Store.CreateDeviceKey(userID, key)
}
func (s *trackingFailureStore) CreateDeviceSession(userID, keyID, token string, expires time.Time) error {
	s.sessions++
	return s.Store.CreateDeviceSession(userID, keyID, token, expires)
}

func TestExchangeShareFailureDoesNotCreateDeviceKeyOrSession(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	s := &trackingFailureStore{failingStore: &failingStore{Store: store.NewMemoryStore(), shareErr: errors.New("database unavailable")}}
	h := New(s)
	h.SetOAuthProvider(exchangeFailureProvider{})
	body := `{"code":"code","code_verifier":"verifier","redirect_uri":"com.jobucaldas.a217://auth/callback","device_public_key":"` + base64.StdEncoding.EncodeToString(der) + `"}`
	w := httptest.NewRecorder()
	h.ExchangeWorkOS(w, httptest.NewRequest(http.MethodPost, "/", strings.NewReader(body)))
	if w.Code != http.StatusServiceUnavailable || s.keys != 0 || s.sessions != 0 {
		t.Fatalf("status = %d, device keys = %d, sessions = %d: %s", w.Code, s.keys, s.sessions, w.Body.String())
	}
}

func TestDeviceSessionShareFailureDoesNotCreateSession(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(deviceSignedMessage("key", "challenge"))
	sig, err := ecdsa.SignASN1(rand.Reader, key, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	s := &trackingFailureStore{failingStore: &failingStore{Store: store.NewMemoryStore(), key: der, user: &model.User{ID: "user"}, shareErr: errors.New("database unavailable")}}
	body := `{"key_id":"key","challenge":"challenge","signature":"` + base64.StdEncoding.EncodeToString(sig) + `"}`
	w := httptest.NewRecorder()
	New(s).DeviceSession(w, httptest.NewRequest(http.MethodPost, "/", strings.NewReader(body)))
	if w.Code != http.StatusServiceUnavailable || s.sessions != 0 {
		t.Fatalf("status = %d, sessions = %d: %s", w.Code, s.sessions, w.Body.String())
	}
}

func TestDeviceSessionStoreFailures(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(deviceSignedMessage("key", "challenge"))
	sig, err := ecdsa.SignASN1(rand.Reader, key, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	body := `{"key_id":"key","challenge":"challenge","signature":"` + base64.StdEncoding.EncodeToString(sig) + `"}`
	failure := errors.New("database unavailable")
	for _, tc := range []struct {
		name                  string
		challengeErr, userErr error
		want                  int
	}{
		{"challenge failure", failure, nil, 503}, {"invalid challenge", store.ErrDeviceChallengeInvalid, nil, 401},
		{"missing key", store.ErrDeviceKeyNotFound, nil, 401}, {"user failure", nil, failure, 503}, {"missing user", nil, store.ErrUserNotFound, 401},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := &failingStore{Store: store.NewMemoryStore(), key: der, challengeErr: tc.challengeErr, userErr: tc.userErr}
			w := httptest.NewRecorder()
			New(s).DeviceSession(w, httptest.NewRequest(http.MethodPost, "/", strings.NewReader(body)))
			if w.Code != tc.want {
				t.Fatalf("status = %d, want %d: %s", w.Code, tc.want, w.Body.String())
			}
		})
	}
}
