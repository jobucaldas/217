package store

import (
	"sync"
	"testing"
	"time"
)

func TestCreatePasswordUserPGCredentialRoundTrip(t *testing.T) {
	s := pgTestStore(t) // skips without TEST_DATABASE_URL

	const hash = "argon2id$1$65536$2$pgsalt$c29tZXNhbHQ"
	user, err := s.CreatePasswordUser("pg-roundtrip@example.com", hash, "", time.Time{})
	if err != nil {
		t.Fatal(err)
	}
	got, err := s.GetPasswordCredential(user.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got != hash {
		t.Fatalf("credential round trip: got %q, want %q", got, hash)
	}
	// The legacy column stays empty: the hash lives only in
	// password_credentials.
	var legacy string
	if err := s.db.QueryRow(`SELECT password_hash FROM users WHERE id = $1`, user.ID).Scan(&legacy); err != nil {
		t.Fatal(err)
	}
	if legacy != "" {
		t.Fatalf("legacy users.password_hash must be empty on signup, got %q", legacy)
	}
}

func TestCreatePasswordUserPGVerificationRow(t *testing.T) {
	s := pgTestStore(t)
	user, err := s.CreatePasswordUser("pg-verify@example.com", "hash-verify", "654321",
		time.Now().UTC().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if pending, err := s.HasEmailVerification(user.ID); err != nil || !pending {
		t.Fatalf("verification row must be written in the same tx, got %v %v", pending, err)
	}
	if ok, err := s.ConsumeEmailVerification(user.ID, "654321"); !ok || err != nil {
		t.Fatalf("stored code must consume, got %v %v", ok, err)
	}
}

func TestCreatePasswordUserPGDuplicateEmail(t *testing.T) {
	s := pgTestStore(t)

	email := "pg-dup@example.com"
	if _, err := s.CreatePasswordUser(email, "hash-one", "", time.Time{}); err != nil {
		t.Fatal(err)
	}
	_, err := s.CreatePasswordUser(email, "hash-two", "", time.Time{})
	if !s.ErrEmailTaken(err) {
		t.Fatalf("expected ErrEmailTaken, got %v", err)
	}
	// The original credential must be untouched.
	id, hash, err := s.LookupPasswordHashByEmail(email)
	if err != nil || id == "" || hash != "hash-one" {
		t.Fatalf("duplicate signup must not touch the first credential: %q %v", hash, err)
	}
}

func TestCreatePasswordUserPGParallelOneWinner(t *testing.T) {
	s := pgTestStore(t)

	const email = "pg-race@example.com"
	const n = 8
	errs := make([]error, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := s.CreatePasswordUser(email, "hash-race", "", time.Time{})
			errs[i] = err
		}()
	}
	wg.Wait()
	winners := 0
	for _, err := range errs {
		if err == nil {
			winners++
		}
	}
	if winners != 1 {
		t.Fatalf("expected exactly one winner, got %d", winners)
	}
}
