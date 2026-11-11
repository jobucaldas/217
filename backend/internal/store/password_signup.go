package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"217/backend/internal/model"
)

// errEmailTaken marks the CreatePasswordUser failure when the email is
// already registered (the handler answers it with 409).
var errEmailTaken = errors.New("email already registered")

// ErrEmailTaken reports whether err is the email-already-registered failure
// of CreatePasswordUser.
func (s *MemoryStore) ErrEmailTaken(err error) bool { return errors.Is(err, errEmailTaken) }

// ErrEmailTaken reports whether err is the email-already-registered failure
// of CreatePasswordUser.
func (s *PGStore) ErrEmailTaken(err error) bool { return errors.Is(err, errEmailTaken) }

// CreatePasswordUser creates the account with its password hash and (when
// code is not empty) the address verification row in one transaction, under
// the same per-email advisory lock as the WorkOS link: concurrent signups
// for one email produce exactly one account, the rest get errEmailTaken.
func (s *MemoryStore) CreatePasswordUser(email, passwordHash, verificationCode string, verificationExpires time.Time) (*model.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	normalized := normalizeEmail(email)
	for _, u := range s.users {
		if normalizeEmail(u.Email) == normalized {
			return nil, errEmailTaken
		}
	}
	now := time.Now().UTC()
	user := &model.User{
		ID:        generateID(),
		Email:     normalized,
		Name:      normalized,
		Stage:     model.StageCycling,
		APIKey:    generateAPIKey(),
		CreatedAt: now,
		UpdatedAt: now,
	}
	s.users[user.APIKey] = user
	s.passwordCredentials[user.ID] = memoryCredential{hash: passwordHash, updatedAt: now}
	if verificationCode != "" {
		s.emailVerifications[user.ID] = memoryVerification{codeHash: hashString(verificationCode), expiresAt: verificationExpires}
	}
	return user, nil
}

// CreatePasswordUser creates the account with its password hash and (when
// code is not empty) the address verification row in one transaction, under
// the same per-email advisory lock as the WorkOS link: concurrent signups
// for one email produce exactly one account, the rest get errEmailTaken.
func (s *PGStore) CreatePasswordUser(email, passwordHash, verificationCode string, verificationExpires time.Time) (*model.User, error) {
	normalized := normalizeEmail(email)
	index := emailIndex(s.kr, normalized)
	tx, err := s.db.BeginTx(context.Background(), &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return nil, fmt.Errorf("beginning signup transaction: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	// Serialize signups for one address (same lock family as the WorkOS link).
	if _, err := tx.Exec(`SELECT pg_advisory_xact_lock(hashtextextended(encode($1::bytea, 'hex'), 218))`, index); err != nil {
		return nil, fmt.Errorf("locking signup email: %w", err)
	}
	var matches int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM users WHERE email_index = $1`, index).Scan(&matches); err != nil {
		return nil, fmt.Errorf("counting email matches: %w", err)
	}
	if matches > 0 {
		return nil, errEmailTaken
	}
	created, err := s.insertUser(tx, normalized, normalized, passwordHash)
	if err != nil {
		return nil, fmt.Errorf("creating user: %w", err)
	}
	if verificationCode != "" {
		if _, err := tx.Exec(`INSERT INTO email_verifications (user_id, code_hash, expires_at) VALUES ($1, $2, $3)`,
			created.ID, hashString(verificationCode), verificationExpires); err != nil {
			return nil, fmt.Errorf("storing verification code: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("committing signup: %w", err)
	}
	return created, nil
}
