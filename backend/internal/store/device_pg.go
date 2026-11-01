package store

import (
	"crypto/subtle"
	"database/sql"
	"fmt"
	"time"

	"217/backend/internal/model"
)

func (s *PGStore) CreateDeviceKey(userID string, publicKey []byte) (string, error) {
	id := generateID()
	tx, err := s.db.Begin()
	if err != nil {
		return "", fmt.Errorf("creating device key: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.Exec(`INSERT INTO device_keys (id, user_id, public_key) VALUES ($1, $2, $3)`,
		id, userID, publicKey); err != nil {
		return "", fmt.Errorf("creating device key: %w", err)
	}
	if _, err := tx.Exec(`DELETE FROM device_keys WHERE user_id = $1 AND id NOT IN (
		SELECT id FROM device_keys WHERE user_id = $1 ORDER BY last_used_at DESC, created_at DESC LIMIT $2)`,
		userID, model.MaxDeviceKeysPerUser); err != nil {
		return "", fmt.Errorf("trimming device keys: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return "", fmt.Errorf("creating device key: %w", err)
	}
	return id, nil
}

func (s *PGStore) CreateDeviceSession(userID, keyID, sessionID string, expiresAt time.Time) error {
	_, _ = s.db.Exec(`DELETE FROM sessions WHERE expires_at <= NOW()`)
	if _, err := s.db.Exec(`INSERT INTO sessions (id, user_id, created_at, expires_at, device_key_id)
		VALUES ($1, $2, NOW(), $3, $4)`, hashString(sessionID), userID, expiresAt, keyID); err != nil {
		return fmt.Errorf("creating device session: %w", err)
	}
	if _, err := s.db.Exec(`UPDATE device_keys SET last_used_at = NOW() WHERE id = $1`, keyID); err != nil {
		return fmt.Errorf("touching device key: %w", err)
	}
	return nil
}

func (s *PGStore) SetDeviceChallenge(keyID, challenge string, expiresAt time.Time) error {
	res, err := s.db.Exec(`UPDATE device_keys SET challenge_hash = $2, challenge_expires_at = $3
		WHERE id = $1 AND last_used_at > $4`,
		keyID, hashString(challenge), expiresAt, time.Now().UTC().Add(-model.DeviceKeyIdleRetention))
	if err != nil {
		return fmt.Errorf("setting device challenge: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return fmt.Errorf("device key not found")
	}
	return nil
}

func (s *PGStore) ConsumeDeviceChallenge(keyID, challenge string) (string, []byte, error) {
	var (
		userID    string
		publicKey []byte
		hash      sql.NullString
		expires   sql.NullTime
	)
	err := s.db.QueryRow(`UPDATE device_keys d SET challenge_hash = NULL, challenge_expires_at = NULL
		FROM (SELECT id, challenge_hash, challenge_expires_at FROM device_keys WHERE id = $1 FOR UPDATE) old
		WHERE d.id = old.id
		RETURNING d.user_id, d.public_key, old.challenge_hash, old.challenge_expires_at`, keyID).
		Scan(&userID, &publicKey, &hash, &expires)
	if err == sql.ErrNoRows {
		return "", nil, fmt.Errorf("device key not found")
	}
	if err != nil {
		return "", nil, fmt.Errorf("consuming device challenge: %w", err)
	}
	if !hash.Valid || !expires.Valid || !time.Now().UTC().Before(expires.Time) ||
		subtle.ConstantTimeCompare([]byte(hash.String), []byte(hashString(challenge))) != 1 {
		return "", nil, fmt.Errorf("invalid or expired challenge")
	}
	return userID, publicKey, nil
}

func (s *PGStore) DeleteSessionAndDevice(sessionID string) error {
	hash := hashString(sessionID)
	if _, err := s.db.Exec(`DELETE FROM device_keys WHERE id = (
		SELECT device_key_id FROM sessions WHERE id = $1)`, hash); err != nil {
		return fmt.Errorf("revoking device key: %w", err)
	}
	return s.DeleteSession(sessionID)
}

func (s *PGStore) ListDeviceKeys(userID string) ([]model.DeviceKey, error) {
	rows, err := s.db.Query(`SELECT id, created_at, last_used_at FROM device_keys
		WHERE user_id = $1 ORDER BY created_at`, userID)
	if err != nil {
		return nil, fmt.Errorf("listing device keys: %w", err)
	}
	defer rows.Close()
	keys := []model.DeviceKey{}
	for rows.Next() {
		var k model.DeviceKey
		if err := rows.Scan(&k.ID, &k.CreatedAt, &k.LastUsedAt); err != nil {
			return nil, fmt.Errorf("scanning device key: %w", err)
		}
		k.CreatedAt, k.LastUsedAt = k.CreatedAt.UTC(), k.LastUsedAt.UTC()
		keys = append(keys, k)
	}
	return keys, rows.Err()
}
