package store

import (
	"crypto/subtle"
	"fmt"
	"sort"
	"time"

	"217/backend/internal/model"
)

type memoryDeviceKey struct {
	UserID           string
	PublicKey        []byte
	CreatedAt        time.Time
	LastUsedAt       time.Time
	ChallengeHash    string
	ChallengeExpires time.Time
}

func (s *MemoryStore) CreateDeviceKey(userID string, publicKey []byte) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.findUserLocked(userID) == nil {
		return "", fmt.Errorf("user not found")
	}
	id := generateID()
	now := time.Now().UTC()
	s.deviceKeys[id] = &memoryDeviceKey{UserID: userID, PublicKey: append([]byte(nil), publicKey...), CreatedAt: now, LastUsedAt: now}
	var mine []string
	for kid, k := range s.deviceKeys {
		if k.UserID == userID {
			mine = append(mine, kid)
		}
	}
	sort.Slice(mine, func(i, j int) bool {
		a, b := s.deviceKeys[mine[i]], s.deviceKeys[mine[j]]
		if !a.LastUsedAt.Equal(b.LastUsedAt) {
			return a.LastUsedAt.After(b.LastUsedAt)
		}
		return mine[i] == id
	})
	for _, kid := range mine[min(len(mine), model.MaxDeviceKeysPerUser):] {
		s.deleteDeviceKeyLocked(kid)
	}
	return id, nil
}

// deleteDeviceKeyLocked revokes a key and the sessions it opened.
func (s *MemoryStore) deleteDeviceKeyLocked(keyID string) {
	delete(s.deviceKeys, keyID)
	for hash, sess := range s.sessions {
		if sess.DeviceKeyID == keyID {
			delete(s.sessions, hash)
		}
	}
}

func (s *MemoryStore) CreateDeviceSession(userID, keyID, sessionID string, expiresAt time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	key, ok := s.deviceKeys[keyID]
	if !ok || key.UserID != userID {
		return fmt.Errorf("device key not found")
	}
	now := time.Now().UTC()
	key.LastUsedAt = now
	s.sessions[hashString(sessionID)] = memorySession{UserID: userID, CreatedAt: now, ExpiresAt: expiresAt, DeviceKeyID: keyID}
	return nil
}

func (s *MemoryStore) SetDeviceChallenge(keyID, challenge string, expiresAt time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	key, ok := s.deviceKeys[keyID]
	if !ok || !key.LastUsedAt.After(time.Now().UTC().Add(-model.DeviceKeyIdleRetention)) {
		return fmt.Errorf("device key not found")
	}
	key.ChallengeHash, key.ChallengeExpires = hashString(challenge), expiresAt
	return nil
}

func (s *MemoryStore) ConsumeDeviceChallenge(keyID, challenge string) (string, []byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	key, ok := s.deviceKeys[keyID]
	if !ok {
		return "", nil, fmt.Errorf("device key not found")
	}
	hash, expires := key.ChallengeHash, key.ChallengeExpires
	key.ChallengeHash, key.ChallengeExpires = "", time.Time{}
	if hash == "" || !time.Now().UTC().Before(expires) ||
		subtle.ConstantTimeCompare([]byte(hash), []byte(hashString(challenge))) != 1 {
		return "", nil, fmt.Errorf("invalid or expired challenge")
	}
	return key.UserID, append([]byte(nil), key.PublicKey...), nil
}

func (s *MemoryStore) DeleteSessionAndDevice(sessionID string) error {
	hash := hashString(sessionID)
	s.mu.Lock()
	defer s.mu.Unlock()
	if sess, ok := s.sessions[hash]; ok && sess.DeviceKeyID != "" {
		s.deleteDeviceKeyLocked(sess.DeviceKeyID)
	}
	delete(s.sessions, hash)
	return nil
}

func (s *MemoryStore) ListDeviceKeys(userID string) ([]model.DeviceKey, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	keys := []model.DeviceKey{}
	for id, k := range s.deviceKeys {
		if k.UserID == userID {
			keys = append(keys, model.DeviceKey{ID: id, CreatedAt: k.CreatedAt, LastUsedAt: k.LastUsedAt})
		}
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i].CreatedAt.Before(keys[j].CreatedAt) })
	return keys, nil
}
