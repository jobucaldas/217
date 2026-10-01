package store

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"217/backend/internal/model"
)

func TestMemoryStore_CreateAndGetUser(t *testing.T) {
	s := NewMemoryStore()

	user, err := s.CreateUser("test@example.com", "Test", "testpass123")
	if err != nil {
		t.Fatalf("CreateUser failed: %v", err)
	}
	if user.Email != "test@example.com" {
		t.Errorf("expected test@example.com, got %s", user.Email)
	}
	if user.APIKey == "" {
		t.Error("expected non-empty API key")
	}

	got, err := s.GetUserByAPIKey(user.APIKey)
	if err != nil {
		t.Fatalf("GetUserByAPIKey failed: %v", err)
	}
	if got.Email != user.Email {
		t.Errorf("email mismatch: %s vs %s", got.Email, user.Email)
	}

	got2, err := s.GetUserByEmail("test@example.com")
	if err != nil {
		t.Fatalf("GetUserByEmail failed: %v", err)
	}
	if got2.ID != user.ID {
		t.Errorf("user ID mismatch")
	}
}

func TestMemoryStore_DuplicateEmail(t *testing.T) {
	s := NewMemoryStore()
	_, err := s.CreateUser("dup@example.com", "First", "testpass123")
	if err != nil {
		t.Fatalf("first create failed: %v", err)
	}
	_, err = s.CreateUser("dup@example.com", "Second", "testpass123")
	if err == nil {
		t.Error("expected error for duplicate email")
	}
}

func TestMemoryStore_UpsertAndGetEntry(t *testing.T) {
	s := NewMemoryStore()
	user, _ := s.CreateUser("u@t.com", "U", "testpass123")

	entry, err := s.UpsertEntry(user.ID, "2026-05-13", model.UpsertRequest{Taken: true, Notes: "ok", Heart: true})
	if err != nil {
		t.Fatalf("UpsertEntry failed: %v", err)
	}
	if !entry.Heart {
		t.Fatalf("expected heart=true on upsert")
	}
	if entry.Date != "2026-05-13" {
		t.Errorf("expected date 2026-05-13, got %s", entry.Date)
	}
	if entry.UserID != user.ID {
		t.Errorf("expected userID %s, got %s", user.ID, entry.UserID)
	}

	got, err := s.GetEntry(user.ID, "2026-05-13")
	if err != nil {
		t.Fatalf("GetEntry failed: %v", err)
	}
	if got.Taken != true {
		t.Errorf("expected taken=true")
	}
	if got.Notes != "ok" {
		t.Errorf("expected notes to persist, got %q", got.Notes)
	}

	_, err = s.UpsertEntry(user.ID, "2026-05-13", model.UpsertRequest{Taken: false, Notes: "updated"})
	if err != nil {
		t.Fatalf("updating entry failed: %v", err)
	}
	got, _ = s.GetEntry(user.ID, "2026-05-13")
	if got.Notes != "updated" {
		t.Errorf("expected updated notes, got %q", got.Notes)
	}

	if err := s.DeleteEntry(user.ID, "2026-05-13"); err != nil {
		t.Fatalf("DeleteEntry failed: %v", err)
	}
	if _, err := s.GetEntry(user.ID, "2026-05-13"); err == nil {
		t.Fatal("expected entry gone after DeleteEntry")
	}
}

func TestMemoryStore_UserEntryIsolation(t *testing.T) {
	s := NewMemoryStore()
	u1, _ := s.CreateUser("u1@t.com", "U1", "testpass123")
	u2, _ := s.CreateUser("u2@t.com", "U2", "testpass123")

	s.UpsertEntry(u1.ID, "2026-05-01", model.UpsertRequest{Taken: true, Notes: ""})
	s.UpsertEntry(u2.ID, "2026-05-01", model.UpsertRequest{Taken: false, Notes: ""})

	e1, _ := s.GetEntry(u1.ID, "2026-05-01")
	if !e1.Taken {
		t.Error("u1 entry should be taken=true")
	}

	e2, _ := s.GetEntry(u2.ID, "2026-05-01")
	if e2.Taken {
		t.Error("u2 entry should be taken=false")
	}
}

func TestMemoryStore_ListEntries(t *testing.T) {
	s := NewMemoryStore()
	u, _ := s.CreateUser("u@t.com", "U", "testpass123")

	s.UpsertEntry(u.ID, "2026-05-01", model.UpsertRequest{Taken: true, Notes: ""})
	s.UpsertEntry(u.ID, "2026-05-15", model.UpsertRequest{Taken: false, Notes: ""})
	s.UpsertEntry(u.ID, "2026-05-31", model.UpsertRequest{Taken: true, Notes: ""})

	entries, err := s.ListEntries(u.ID, 2026, 5)
	if err != nil {
		t.Fatalf("ListEntries failed: %v", err)
	}
	if len(entries) != 3 {
		t.Errorf("expected 3 entries, got %d", len(entries))
	}
}

func TestMemoryStore_RemindersAreUserScopedAndLimited(t *testing.T) {
	s := NewMemoryStore()
	userA, _ := s.CreateUser("a-reminder@example.com", "A", "password")
	userB, _ := s.CreateUser("b-reminder@example.com", "B", "password")
	request := model.PushSubscriptionRequest{Endpoint: "https://push.example/shared"}
	request.Keys.P256DH, request.Keys.Auth = "key", "auth"
	if _, err := s.SavePushSubscription(userA.ID, request); err != nil {
		t.Fatal(err)
	}
	if _, err := s.SavePushSubscription(userB.ID, request); err == nil {
		t.Fatal("another user took over an existing endpoint")
	}
	if err := s.DeletePushSubscription(userB.ID, request.Endpoint); err != nil {
		t.Fatal(err)
	}
	if count, _ := s.CountPushSubscriptions(userA.ID); count != 1 {
		t.Fatalf("another user deleted the endpoint; count=%d", count)
	}
	for i := 1; i < model.MaxPushSubscriptions; i++ {
		request.Endpoint = fmt.Sprintf("https://push.example/%d", i)
		if _, err := s.SavePushSubscription(userA.ID, request); err != nil {
			t.Fatal(err)
		}
	}
	request.Endpoint = "https://push.example/too-many"
	if _, err := s.SavePushSubscription(userA.ID, request); err == nil {
		t.Fatal("subscription quota was not enforced")
	}
}

func TestMemoryStore_GetEntryNotFound(t *testing.T) {
	s := NewMemoryStore()
	u, _ := s.CreateUser("u@t.com", "U", "testpass123")
	_, err := s.GetEntry(u.ID, "2099-01-01")
	if err == nil {
		t.Error("expected error for non-existent entry")
	}
}

func TestMemoryStore_LinkWorkOSIdentityUsesNormalizedEmailAndDurableSubject(t *testing.T) {
	s := NewMemoryStore()
	user, _ := s.CreateUser("Linked@Example.com", "U", "testpass123")

	linked, err := s.LinkWorkOSIdentity("subject-a", "linked@example.com", "Linked", true)
	if err != nil {
		t.Fatalf("LinkWorkOSIdentity failed: %v", err)
	}
	if linked.ID != user.ID {
		t.Fatalf("expected same user ID, got %s", linked.ID)
	}
	if linked.APIKey != "" || linked.PasswordHash != "" {
		t.Fatalf("linked user must be sanitized: %#v", linked)
	}

	again, err := s.LinkWorkOSIdentity("subject-a", "different@example.com", "Different", false)
	if err != nil {
		t.Fatalf("durable subject failed: %v", err)
	}
	if again.ID != user.ID {
		t.Fatalf("expected durable subject to reuse user, got %s", again.ID)
	}

	if _, err := s.LinkWorkOSIdentity("subject-b", "linked@example.com", "Linked", true); err == nil {
		t.Fatal("must not link another subject by email")
	}
}

func TestMemoryStore_LinkWorkOSIdentityCreatesOAuthUser(t *testing.T) {
	s := NewMemoryStore()
	created, err := s.LinkWorkOSIdentity("new-subject", "New@Example.com", "New User", true)
	if err != nil {
		t.Fatal(err)
	}
	if created.Email != "new@example.com" || created.Name != "New User" {
		t.Fatalf("unexpected user: %#v", created)
	}
	again, err := s.LinkWorkOSIdentity("new-subject", "changed@example.com", "Changed", true)
	if err != nil || again.ID != created.ID {
		t.Fatalf("subject was not durable: %#v, %v", again, err)
	}
}

func TestMemoryStore_OAuthAttemptOneTimeAndExpiring(t *testing.T) {
	s := NewMemoryStore()
	if err := s.CreateOAuthAttempt("state-1", "binding-1", "verifier-1", "nonce-1", time.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	verifier, err := s.ConsumeOAuthAttempt("state-1", "binding-1")
	if err != nil {
		t.Fatal(err)
	}
	if verifier.CodeVerifier != "verifier-1" || verifier.Nonce != "nonce-1" {
		t.Fatalf("expected verifier to round-trip, got %#v", verifier)
	}
	if _, err := s.ConsumeOAuthAttempt("state-1", "binding-1"); err == nil {
		t.Fatal("expected one-time state to be rejected on reuse")
	}
	if err := s.CreateOAuthAttempt("state-2", "binding-2", "verifier-2", "nonce-2", time.Now().Add(-time.Minute)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ConsumeOAuthAttempt("state-2", "binding-2"); err == nil {
		t.Fatal("expected expired state to be rejected")
	}
	if err := s.CreateOAuthAttempt("state-3", "binding-3", "verifier-3", "nonce-3", time.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ConsumeOAuthAttempt("state-3", "wrong-binding"); err == nil {
		t.Fatal("expected mismatched browser binding to be rejected")
	}
	if verifier, err := s.ConsumeOAuthAttempt("state-3", "binding-3"); err != nil || verifier.CodeVerifier != "verifier-3" || verifier.Nonce != "nonce-3" {
		t.Fatalf("binding mismatch must not consume attempt: verifier=%#v err=%v", verifier, err)
	}
}

func TestMemoryStore_LinkWorkOSIdentityRejectsAmbiguousNormalizedEmail(t *testing.T) {
	s := NewMemoryStore()
	if _, err := s.CreateUser("User@example.com", "One", "password123"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateUser("user@example.com", "Two", "password123"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.LinkWorkOSIdentity("subject", "USER@example.com", "WorkOS User", true); err == nil || !strings.Contains(err.Error(), "ambiguous normalized email") {
		t.Fatalf("expected ambiguous-email failure, got %v", err)
	}
}
