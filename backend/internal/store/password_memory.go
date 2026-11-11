package store

import (
	"crypto/subtle"
	"fmt"
	"time"
)

// password credentials for the memory store (see memory.go for the mutex).
type memoryCredential struct {
	hash      string
	updatedAt time.Time
}

// pending email verification (one per user, replaced on resend).
type memoryVerification struct {
	codeHash  string
	expiresAt time.Time
}

func (s *MemoryStore) SetPasswordCredential(userID string, hash string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.findUserLocked(userID) == nil {
		return fmt.Errorf("user not found")
	}
	s.passwordCredentials[userID] = memoryCredential{hash: hash, updatedAt: time.Now().UTC()}
	return nil
}

func (s *MemoryStore) GetPasswordCredential(userID string) (string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if c, ok := s.passwordCredentials[userID]; ok {
		return c.hash, nil
	}
	return "", nil
}

func (s *MemoryStore) LookupPasswordHashByEmail(email string) (string, string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	normalized := normalizeEmail(email)
	for _, u := range s.users {
		if normalizeEmail(u.Email) == normalized {
			if c, ok := s.passwordCredentials[u.ID]; ok {
				return u.ID, c.hash, nil
			}
			return u.ID, "", nil
		}
	}
	return "", "", nil
}

func (s *MemoryStore) CreateEmailVerification(userID, code string, expiresAt time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.findUserLocked(userID) == nil {
		return fmt.Errorf("user not found")
	}
	s.emailVerifications[userID] = memoryVerification{codeHash: hashString(code), expiresAt: expiresAt}
	return nil
}

func (s *MemoryStore) HasEmailVerification(userID string) (bool, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	// A pending verification gates sign-in however old it is: an expired
	// code still means the address was never verified (resend renews it).
	_, pending := s.emailVerifications[userID]
	return pending, nil
}

func (s *MemoryStore) ConsumeEmailVerification(userID, code string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	v, ok := s.emailVerifications[userID]
	if !ok || time.Now().UTC().After(v.expiresAt) {
		return false, nil
	}
	// Constant-time compare so the check does not leak the code.
	if subtle.ConstantTimeCompare([]byte(v.codeHash), []byte(hashString(code))) != 1 {
		return false, nil
	}
	delete(s.emailVerifications, userID)
	return true, nil
}

func (s *MemoryStore) DeletePasswordCredential(userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.passwordCredentials, userID)
	return nil
}
