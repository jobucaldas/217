package handler

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"217/backend/internal/model"
	"217/backend/internal/store"
)

type failedReminderWrite struct{ store.Store }

var errReminderWrite = errors.New("write failed")

func (failedReminderWrite) UpsertReminderPreference(string, model.ReminderPreference) (*model.ReminderPreference, error) {
	return nil, errReminderWrite
}
func (failedReminderWrite) SavePushSubscription(string, model.PushSubscriptionRequest) (*model.PushSubscription, error) {
	return nil, errReminderWrite
}
func (failedReminderWrite) DeletePushSubscription(string, string) error { return errReminderWrite }
func (failedReminderWrite) SetRole(string, string) (*model.User, error) { return nil, errReminderWrite }
func (failedReminderWrite) RecordConsent(string, int) (*model.User, error) {
	return nil, errReminderWrite
}
func (failedReminderWrite) DeleteUser(string) error { return errReminderWrite }
func (failedReminderWrite) AcceptShare(string, string) (*model.ShareState, error) {
	return nil, errReminderWrite
}

func TestReminderNotifierRunsOnlyAfterSuccessfulMutation(t *testing.T) {
	key := func(size int) string { return base64.RawURLEncoding.EncodeToString(make([]byte, size)) }
	for _, tc := range []struct {
		name, method, body string
		serve              func(*Handler, http.ResponseWriter, *http.Request)
		success, failure   int
	}{
		{"preference", "PUT", `{"enabled":true,"time":"20:00","timezone":"UTC"}`, (*Handler).UpsertReminderPreference, 200, 500},
		{"subscribe", "POST", fmt.Sprintf(`{"endpoint":"https://push.example/sub","keys":{"p256dh":%q,"auth":%q}}`, key(65), key(16)), (*Handler).SavePushSubscription, 201, 409},
		{"unsubscribe", "DELETE", `{"endpoint":"https://push.example/sub"}`, (*Handler).DeletePushSubscription, 204, 500},
		{"role", "PUT", `{"role":"partner"}`, (*Handler).SetRole, 200, 500},
		{"consent", "PUT", fmt.Sprintf(`{"version":%d}`, model.ConsentVersion), (*Handler).RecordConsent, 200, 500},
		{"withdraw", "DELETE", ``, (*Handler).WithdrawConsent, 200, 500},
		{"account", "DELETE", ``, (*Handler).DeleteAccount, 204, 500},
		{"invite", "POST", ``, (*Handler).AcceptShare, 200, 500},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ms := store.NewMemoryStore()
			user, err := ms.LinkWorkOSIdentity("test-user", "user@example.com", "User", true)
			if err != nil {
				t.Fatal(err)
			}
			body := tc.body
			if tc.name == "invite" {
				owner, err := ms.LinkWorkOSIdentity("invite-owner", "owner@example.com", "Owner", true)
				if err != nil {
					t.Fatal(err)
				}
				if _, err = ms.SetRole(owner.ID, model.RoleOwner); err != nil {
					t.Fatal(err)
				}
				if _, err = ms.RecordConsent(owner.ID, model.ConsentVersion); err != nil {
					t.Fatal(err)
				}
				invite, err := ms.EnableShare(owner.ID)
				if err != nil {
					t.Fatal(err)
				}
				body = fmt.Sprintf(`{"code":%q}`, invite.InviteCode)
			}
			for _, run := range []struct {
				store         store.Store
				status, calls int
			}{{failedReminderWrite{ms}, tc.failure, 0}, {ms, tc.success, 1}} {
				h := NewWithVAPID(run.store, "public-key")
				calls := 0
				h.SetReminderNotifier(func() { calls++ })
				r := httptest.NewRequest(tc.method, "/", strings.NewReader(body))
				r = r.WithContext(context.WithValue(r.Context(), userIDKey, user.ID))
				w := httptest.NewRecorder()
				tc.serve(h, w, r)
				if w.Code != run.status || calls != run.calls {
					t.Errorf("status = %d, notifications = %d; want %d, %d: %s", w.Code, calls, run.status, run.calls, w.Body)
				}
			}
		})
	}
}
