package store

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// Both stores must enforce the same ownership boundary, including nonce replay.
func TestWorkOSIdentityStoreContract(t *testing.T) {
	t.Run("memory", func(t *testing.T) { testWorkOSIdentityStore(t, NewMemoryStore()) })
	t.Run("postgres", func(t *testing.T) { testWorkOSIdentityStore(t, pgTestStore(t)) })
}

func TestRefreshVerificationStoreContract(t *testing.T) {
	for _, tc := range []struct {
		name  string
		store func(*testing.T) Store
	}{
		{"memory", func(t *testing.T) Store { return NewMemoryStore() }},
		{"postgres", func(t *testing.T) Store { return pgTestStore(t) }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := tc.store(t)
			u, err := s.CreateUser("refresh@example.com", "User", "")
			if err != nil {
				t.Fatal(err)
			}
			expires := time.Now().Add(time.Hour)
			if ok, err := s.RefreshEmailVerification(u.ID, "new", expires); err != nil || ok {
				t.Fatalf("missing: %v %v", ok, err)
			}
			if err := s.CreateEmailVerification(u.ID, "old", expires); err != nil {
				t.Fatal(err)
			}
			if ok, err := s.RefreshEmailVerification(u.ID, "new", expires); err != nil || !ok {
				t.Fatalf("refresh: %v %v", ok, err)
			}
			if ok, err := s.ConsumeEmailVerification(u.ID, "old"); err != nil || ok {
				t.Fatalf("old: %v %v", ok, err)
			}
			if ok, err := s.ConsumeEmailVerification(u.ID, "new"); err != nil || !ok {
				t.Fatalf("new: %v %v", ok, err)
			}
			if ok, err := s.RefreshEmailVerification(u.ID, "later", expires); err != nil || ok {
				t.Fatalf("consumed: %v %v", ok, err)
			}
		})
	}
}

func testWorkOSIdentityStore(t *testing.T, s Store) {
	t.Helper()
	legacy, err := s.CreateUser("Legacy@example.com", "Legacy", "password123")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.LinkWorkOSIdentity("external", "legacy@example.com", "External", false); err == nil {
		t.Fatal("external email inherited legacy account")
	}
	linked, err := s.LinkWorkOSIdentity("authoritative", "legacy@example.com", "Owner", true)
	if err != nil || linked.ID != legacy.ID {
		t.Fatalf("authoritative link: %v", err)
	}
	again, err := s.LinkWorkOSIdentity("authoritative", "changed@example.net", "Owner", false)
	if err != nil || again.ID != legacy.ID {
		t.Fatalf("subject lookup: %v", err)
	}
	if _, err := s.LinkWorkOSIdentity("another", "legacy@example.com", "Other", true); err == nil {
		t.Fatal("different subject inherited linked account")
	}
	passwordUser, err := s.CreatePasswordUser("password@example.com", "hash", "", time.Time{})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.LinkWorkOSIdentity("password-subject", "password@example.com", "Password", true); err == nil {
		t.Fatal("password account automatically linked")
	}
	if subject, err := s.WorkOSSubject(passwordUser.ID); err != nil || subject != "" {
		t.Fatalf("password account identity changed: %q %v", subject, err)
	}
	created, err := s.LinkWorkOSIdentity("new-external", "new@example.net", "New", false)
	if err != nil || created.ID == legacy.ID {
		t.Fatalf("new external account: %v", err)
	}
	for _, email := range []string{"Ambiguous@example.com", "ambiguous@example.com"} {
		if _, err := s.CreateUser(email, "Legacy", "password123"); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := s.LinkWorkOSIdentity("ambiguous", "AMBIGUOUS@example.com", "Ambiguous", true); err == nil {
		t.Fatal("ambiguous email accepted")
	}
	if err := s.CreateOAuthAttempt("one-time", "browser", "verifier", "independent-nonce", "", time.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ConsumeOAuthAttempt("one-time", "wrong-browser"); err == nil {
		t.Fatal("wrong browser accepted")
	}
	var successes atomic.Int32
	var workers sync.WaitGroup
	for range 4 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			attempt, err := s.ConsumeOAuthAttempt("one-time", "browser")
			if err == nil {
				successes.Add(1)
				if attempt.Nonce != "independent-nonce" || attempt.CodeVerifier != "verifier" {
					t.Error("attempt secrets did not round-trip")
				}
			}
		}()
	}
	workers.Wait()
	if successes.Load() != 1 {
		t.Fatalf("successful consumes = %d, want 1", successes.Load())
	}
}
