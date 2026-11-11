package store

import (
	"testing"
	"time"
)

// TestPasswordCredentialsPG covers the password_credential and email
// verification store contract against PostgreSQL (migration 027).
func TestPasswordCredentialsPG(t *testing.T) {
	s := pgTestStore(t)
	user, err := s.CreateUser("pw-pg@example.com", "PW", "")
	if err != nil {
		t.Fatal(err)
	}

	// Set, get.
	if err := s.SetPasswordCredential(user.ID, "argon2id$1$65536$2$salt$hash"); err != nil {
		t.Fatal(err)
	}
	hash, err := s.GetPasswordCredential(user.ID)
	if err != nil || hash != "argon2id$1$65536$2$salt$hash" {
		t.Fatalf("get credential: %q, %v", hash, err)
	}

	// Replace.
	if err := s.SetPasswordCredential(user.ID, "argon2id$1$65536$2$salt2$hash2"); err != nil {
		t.Fatal(err)
	}
	if hash, _ = s.GetPasswordCredential(user.ID); hash != "argon2id$1$65536$2$salt2$hash2" {
		t.Fatalf("credential not replaced: %q", hash)
	}

	// Lookup by email finds it; unknown emails find nothing.
	id, hash, err := s.LookupPasswordHashByEmail("PW-PG@example.com")
	if err != nil || id != user.ID || hash != "argon2id$1$65536$2$salt2$hash2" {
		t.Fatalf("lookup by email: %q %q %v", id, hash, err)
	}
	if id, hash, _ := s.LookupPasswordHashByEmail("nobody@example.com"); id != "" || hash != "" {
		t.Fatalf("unknown email must miss, got %q %q", id, hash)
	}

	// Email verification: create, pending, consume (single-use).
	expires := time.Now().UTC().Add(time.Hour)
	if err := s.CreateEmailVerification(user.ID, "123456", expires); err != nil {
		t.Fatal(err)
	}
	if pending, err := s.HasEmailVerification(user.ID); err != nil || !pending {
		t.Fatalf("verification must be pending, got %v %v", pending, err)
	}
	if ok, err := s.ConsumeEmailVerification(user.ID, "wrong"); ok || err != nil {
		t.Fatalf("wrong code must not consume, got %v %v", ok, err)
	}
	if ok, err := s.ConsumeEmailVerification(user.ID, "123456"); !ok || err != nil {
		t.Fatalf("right code must consume, got %v %v", ok, err)
	}
	if pending, _ := s.HasEmailVerification(user.ID); pending {
		t.Fatal("consumed verification must be gone")
	}
	if ok, _ := s.ConsumeEmailVerification(user.ID, "123456"); ok {
		t.Fatal("code must be single-use")
	}

	// Expired codes are not pending and cannot be consumed.
	if err := s.CreateEmailVerification(user.ID, "654321", time.Now().UTC().Add(-time.Minute)); err != nil {
		t.Fatal(err)
	}
	if pending, _ := s.HasEmailVerification(user.ID); pending {
		t.Fatal("expired verification must not be pending")
	}
	if ok, _ := s.ConsumeEmailVerification(user.ID, "654321"); ok {
		t.Fatal("expired code must not consume")
	}

	// Delete credential.
	if err := s.DeletePasswordCredential(user.ID); err != nil {
		t.Fatal(err)
	}
	if hash, _ := s.GetPasswordCredential(user.ID); hash != "" {
		t.Fatalf("deleted credential must be gone, got %q", hash)
	}

	// ON DELETE CASCADE: deleting the user removes the leftover rows.
	if err := s.CreateEmailVerification(user.ID, "999999", time.Now().UTC().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := s.SetPasswordCredential(user.ID, "argon2id$1$65536$2$s$ha"); err != nil {
		t.Fatal(err)
	}
	if err := s.DeleteUser(user.ID); err != nil {
		t.Fatal(err)
	}
	var n int
	if err := s.db.QueryRow(`SELECT count(*) FROM password_credentials WHERE user_id = $1`, user.ID).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("password_credentials rows must cascade, got %d", n)
	}
	if err := s.db.QueryRow(`SELECT count(*) FROM email_verifications WHERE user_id = $1`, user.ID).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("email_verifications rows must cascade, got %d", n)
	}
}

// TestEmailVerificationsHoldOnlyHashes checks that no plaintext code is
// stored: the table column is code_hash and a raw lookup for the code fails.
func TestEmailVerificationsHoldOnlyHashes(t *testing.T) {
	s := pgTestStore(t)
	user, err := s.CreateUser("hash-pg@example.com", "H", "")
	if err != nil {
		t.Fatal(err)
	}
	if err := s.CreateEmailVerification(user.ID, "246810", time.Now().UTC().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	var n int
	if err := s.db.QueryRow(`SELECT count(*) FROM email_verifications WHERE code_hash = $1`, "246810").Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatal("plaintext code found in email_verifications")
	}
}
