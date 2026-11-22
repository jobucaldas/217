package store

import (
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// Password credentials live in their own table (password_credentials); the
// legacy users.password_hash column is left alone.

// ResetPasswordCredential atomically replaces the credential and revokes access.
func (s *PGStore) ResetPasswordCredential(userID, hash string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err = tx.Exec(`INSERT INTO password_credentials (user_id, hash)
		VALUES ($1, $2) ON CONFLICT (user_id) DO UPDATE
		SET hash = EXCLUDED.hash, updated_at = NOW()`, userID, hash); err != nil {
		return fmt.Errorf("storing password credential: %w", err)
	}
	if _, err = tx.Exec(`DELETE FROM sessions WHERE user_id = $1`, userID); err != nil {
		return fmt.Errorf("revoking sessions: %w", err)
	}
	if _, err = tx.Exec(`DELETE FROM device_keys WHERE user_id = $1`, userID); err != nil {
		return fmt.Errorf("revoking devices: %w", err)
	}
	return tx.Commit()
}

func (s *PGStore) RemoveSignInMethod(userID, issuer string, password, passwordEnabled, workosEnabled bool) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var locked string
	if err := tx.QueryRow(`SELECT id FROM users WHERE id=$1 FOR UPDATE`, userID).Scan(&locked); err != nil {
		return err
	}
	var other bool
	if password {
		err = tx.QueryRow(`SELECT ($2 AND EXISTS (SELECT 1 FROM workos_identities WHERE user_id=$1)) OR ($3 <> '' AND EXISTS (SELECT 1 FROM oidc_identities WHERE user_id=$1 AND issuer=$3))`, userID, workosEnabled, issuer).Scan(&other)
	} else {
		err = tx.QueryRow(`SELECT ($2 AND EXISTS (SELECT 1 FROM workos_identities WHERE user_id=$1)) OR ($3 AND EXISTS (SELECT 1 FROM password_credentials WHERE user_id=$1))`, userID, workosEnabled, passwordEnabled).Scan(&other)
	}
	if err != nil {
		return err
	}
	if !other {
		return ErrOnlySignInMethod
	}
	if password {
		_, err = tx.Exec(`DELETE FROM password_credentials WHERE user_id=$1`, userID)
	} else {
		_, err = tx.Exec(`DELETE FROM oidc_identities WHERE user_id=$1 AND issuer=$2`, userID, issuer)
	}
	if err != nil {
		return err
	}
	return tx.Commit()
}

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
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil // a user without a password, not an error
	}
	if err != nil {
		return "", fmt.Errorf("getting password credential: %w", err)
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

func (s *PGStore) RefreshEmailVerification(userID, code string, expiresAt time.Time) (bool, error) {
	res, err := s.db.Exec(`UPDATE email_verifications SET code_hash = $2, expires_at = $3 WHERE user_id = $1`, userID, hashString(code), expiresAt)
	if err != nil {
		return false, fmt.Errorf("refreshing email verification: %w", err)
	}
	n, err := res.RowsAffected()
	return n > 0, err
}

func (s *PGStore) HasEmailVerification(userID string) (bool, error) {
	// A pending verification gates sign-in however old it is: an expired
	// code still means the address was never verified (resend renews it).
	var pending bool
	err := s.db.QueryRow(`SELECT EXISTS (
		SELECT 1 FROM email_verifications WHERE user_id = $1)`, userID).Scan(&pending)
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
