package store

import (
	"fmt"
	"time"
)

// Password credentials live in their own table (password_credentials); the
// legacy users.password_hash column is left alone.

func (s *PGStore) SetPasswordCredential(userID string, hash string) error {
	_, err := s.db.Exec(`INSERT INTO password_credentials (user_id, hash)
		VALUES ($1, $2)
		ON CONFLICT (user_id) DO UPDATE SET hash = EXCLUDED.hash, updated_at = NOW()`,
		userID, hash)
	if err != nil {
		return fmt.Errorf("storing password credential: %w", err)
	}
	return nil
}

func (s *PGStore) GetPasswordCredential(userID string) (string, error) {
	var hash string
	err := s.db.QueryRow(`SELECT hash FROM password_credentials WHERE user_id = $1`, userID).Scan(&hash)
	if err != nil {
		// A missing row is a user without a password, not an error.
		return "", nil
	}
	return hash, nil
}

func (s *PGStore) DeletePasswordCredential(userID string) error {
	_, err := s.db.Exec(`DELETE FROM password_credentials WHERE user_id = $1`, userID)
	if err != nil {
		return fmt.Errorf("deleting password credential: %w", err)
	}
	return nil
}

func (s *PGStore) LookupPasswordHashByEmail(email string) (string, string, error) {
	query := `SELECT u.id, pc.hash FROM users u
		JOIN password_credentials pc ON pc.user_id = u.id
		WHERE u.email_index = $1 LIMIT 1`
	var userID, hash string
	err := s.db.QueryRow(query, emailIndex(s.kr, normalizeEmail(email))).Scan(&userID, &hash)
	if err != nil {
		// No credential row (or no user) is a sign-in miss, not an error.
		return "", "", nil
	}
	return userID, hash, nil
}

func (s *PGStore) CreateEmailVerification(userID, code string, expiresAt time.Time) error {
	_, err := s.db.Exec(`INSERT INTO email_verifications (user_id, code_hash, expires_at)
		VALUES ($1, $2, $3)
		ON CONFLICT (user_id) DO UPDATE SET code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at`,
		userID, hashString(code), expiresAt)
	if err != nil {
		return fmt.Errorf("storing email verification: %w", err)
	}
	return nil
}

func (s *PGStore) HasEmailVerification(userID string) (bool, error) {
	var pending bool
	err := s.db.QueryRow(`SELECT EXISTS (
		SELECT 1 FROM email_verifications WHERE user_id = $1 AND expires_at > NOW())`, userID).Scan(&pending)
	if err != nil {
		return false, fmt.Errorf("checking email verification: %w", err)
	}
	return pending, nil
}

func (s *PGStore) ConsumeEmailVerification(userID, code string) (bool, error) {
	res, err := s.db.Exec(`DELETE FROM email_verifications
		WHERE user_id = $1 AND code_hash = $2 AND expires_at > NOW()`, userID, hashString(code))
	if err != nil {
		return false, fmt.Errorf("consuming email verification: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("counting consumed verification: %w", err)
	}
	return n > 0, nil
}
