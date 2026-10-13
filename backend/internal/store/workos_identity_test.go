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
	if err := s.CreateOAuthAttempt("one-time", "browser", "verifier", "independent-nonce", time.Now().Add(time.Minute)); err != nil {
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
