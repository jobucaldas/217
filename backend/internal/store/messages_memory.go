package store

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"217/backend/internal/model"
)

func (s *MemoryStore) unreadMessagesLocked(userID string) int {
	n := 0
	for _, m := range s.messages {
		if m.RecipientID() == userID && m.ReadAt == nil {
			n++
		}
	}
	return n
}

func (s *MemoryStore) ListMessages(userID string) ([]*model.Message, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.findUserLocked(userID) == nil {
		return nil, fmt.Errorf("user not found")
	}
	out := make([]*model.Message, 0)
	for _, m := range s.messages {
		if m.OwnerID != userID && m.PartnerID != userID {
			continue
		}
		c := *m
		c.FromMe = m.SenderID() == userID
		c.FromName, c.FromEmail = "", ""
		if from := s.findUserLocked(m.SenderID()); from != nil {
			c.FromName, c.FromEmail = from.Name, from.Email
		}
		out = append(out, &c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}

func (s *MemoryStore) SendMessage(senderID, body string) (*model.Message, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return nil, fmt.Errorf("message body required")
	}
	if len(body) > 2000 {
		return nil, fmt.Errorf("message too long")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	user := s.findUserLocked(senderID)
	if user == nil {
		return nil, fmt.Errorf("user not found")
	}
	m := &model.Message{ID: generateID(), Body: body, CreatedAt: time.Now().UTC(), FromName: user.Name, FromEmail: user.Email}
	var recipient *model.User
	consentErr := "calendar owner consent required"
	switch model.NormalizeRole(user.Role) {
	case model.RolePartner:
		live := s.liveShareForPartnerLocked(senderID)
		if live == nil || live.Status != model.ShareActive {
			return nil, fmt.Errorf("share inactive")
		}
		m.Sender, m.OwnerID, m.PartnerID = model.RolePartner, live.OwnerID, senderID
		recipient = s.findUserLocked(live.OwnerID)
	case model.RoleOwner:
		live := s.liveShareForOwnerLocked(senderID)
		if live == nil || live.Status != model.ShareActive || live.PartnerID == "" {
			return nil, fmt.Errorf("share inactive")
		}
		m.Sender, m.OwnerID, m.PartnerID = model.RoleOwner, senderID, live.PartnerID
		recipient = s.findUserLocked(live.PartnerID)
		consentErr = "partner consent required"
	default:
		return nil, fmt.Errorf("share inactive")
	}
	if !recipient.HasConsent() {
		return nil, fmt.Errorf("%s", consentErr)
	}
	s.messages[m.ID] = m
	c := *m
	c.FromMe = true
	return &c, nil
}

func (s *MemoryStore) MarkMessageRead(userID, messageID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	m, ok := s.messages[messageID]
	if !ok || m.RecipientID() != userID {
		return fmt.Errorf("message not found")
	}
	if m.ReadAt == nil {
		now := time.Now().UTC()
		m.ReadAt = &now
	}
	return nil
}
