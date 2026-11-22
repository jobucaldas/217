package store

import (
	"fmt"
	"time"

	"217/backend/internal/model"
)

type oidcIdentity struct{ issuer, subject string }

func (s *MemoryStore) LinkOIDCIdentity(issuer, subject, email, name string, verified bool) (*model.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := oidcIdentity{issuer, subject}
	if id := s.oidcSubjects[key]; id != "" {
		if u := s.findUserLocked(id); u != nil {
			return sanitizeUser(u), nil
		}
		return nil, fmt.Errorf("identity user not found")
	}
	email = normalizeEmail(email)
	var u *model.User
	for _, candidate := range s.users {
		if normalizeEmail(candidate.Email) == email {
			if u != nil {
				return nil, fmt.Errorf("ambiguous email")
			}
			u = candidate
		}
	}
	if u != nil {
		if !verified {
			return nil, fmt.Errorf("account exists: sign in and connect from settings")
		}
		for identity, id := range s.oidcSubjects {
			if identity.issuer == issuer && id == u.ID {
				return nil, fmt.Errorf("account already linked to another identity")
			}
		}
	} else {
		if name == "" {
			name = email
		}
		now := time.Now().UTC()
		u = &model.User{ID: generateID(), Email: email, Name: name, Stage: model.StageCycling, APIKey: generateAPIKey(), CreatedAt: now, UpdatedAt: now}
		s.users[u.APIKey] = u
	}
	s.oidcSubjects[key] = u.ID
	return sanitizeUser(u), nil
}

func (s *MemoryStore) AttachOIDCIdentity(userID, issuer, subject string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.findUserLocked(userID) == nil {
		return fmt.Errorf("user not found")
	}
	key := oidcIdentity{issuer, subject}
	if _, exists := s.oidcSubjects[key]; exists {
		return fmt.Errorf("identity already linked")
	}
	for identity, id := range s.oidcSubjects {
		if identity.issuer == issuer && id == userID {
			return fmt.Errorf("account already linked")
		}
	}
	s.oidcSubjects[key] = userID
	return nil
}

func (s *MemoryStore) DeleteOIDCIdentity(userID, issuer string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for identity, id := range s.oidcSubjects {
		if identity.issuer == issuer && id == userID {
			delete(s.oidcSubjects, identity)
		}
	}
	return nil
}

func (s *MemoryStore) OIDCIdentities(userID string) ([]model.OIDCIdentity, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var identities []model.OIDCIdentity
	for identity, id := range s.oidcSubjects {
		if id == userID {
			identities = append(identities, model.OIDCIdentity{Issuer: identity.issuer, Subject: identity.subject})
		}
	}
	return identities, nil
}
