package store

import (
	"crypto/rand"
	"fmt"
	"strings"
	"time"

	"217/backend/internal/model"
)

const inviteAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func generateInviteCode() (string, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	out := make([]byte, 8)
	for i := range b {
		out[i] = inviteAlphabet[int(b[i])%len(inviteAlphabet)]
	}
	return string(out), nil
}

func normalizeInviteCode(code string) string {
	return strings.ToUpper(strings.TrimSpace(code))
}

func (s *MemoryStore) GetUserByID(userID string) (*model.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, u := range s.users {
		if u.ID == userID {
			return sanitizeUser(u), nil
		}
	}
	return nil, fmt.Errorf("user not found")
}

func (s *MemoryStore) WorkOSSubject(userID string) (string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for subject, uid := range s.workosSubjects {
		if uid == userID {
			return subject, nil
		}
	}
	return "", nil
}

func (s *MemoryStore) DeleteUser(userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	var apiKey string
	for k, u := range s.users {
		if u.ID == userID {
			apiKey = k
			break
		}
	}
	if apiKey == "" {
		return fmt.Errorf("user not found")
	}

	delete(s.users, apiKey)
	for k, e := range s.entries {
		if e.UserID == userID {
			delete(s.entries, k)
		}
	}
	delete(s.preferences, userID)
	delete(s.partnerAlerts, userID)
	for endpoint, sub := range s.subscriptions {
		if sub.UserID == userID {
			delete(s.subscriptions, endpoint)
		}
	}
	for subject, uid := range s.workosSubjects {
		if uid == userID {
			delete(s.workosSubjects, subject)
		}
	}
	for k, sess := range s.sessions {
		if sess.UserID == userID {
			delete(s.sessions, k)
		}
	}
	for id, share := range s.shares {
		switch {
		case share.OwnerID == userID:
			delete(s.shares, id)
		case share.PartnerID == userID:
			share.PartnerID = ""
			if share.Status == model.ShareOpen || share.Status == model.ShareActive {
				share.Status = model.ShareRevoked
				share.UpdatedAt = time.Now().UTC()
			}
		}
	}
	for id, note := range s.partnerNotes {
		if note.OwnerID == userID || note.PartnerID == userID {
			delete(s.partnerNotes, id)
		}
	}
	return nil
}

func (s *MemoryStore) RecordConsent(userID string, version int) (*model.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	u := s.findUserLocked(userID)
	if u == nil {
		return nil, fmt.Errorf("user not found")
	}
	now := time.Now().UTC()
	u.ConsentVersion, u.ConsentedAt, u.UpdatedAt = version, &now, now
	return sanitizeUser(u), nil
}

func (s *MemoryStore) PurgeExpired(now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for k, sess := range s.sessions {
		if !now.Before(sess.ExpiresAt) {
			delete(s.sessions, k)
		}
	}
	for k, a := range s.oauthAttempts {
		if !now.Before(a.ExpiresAt) {
			delete(s.oauthAttempts, k)
		}
	}
	for key, delivery := range s.deliveries {
		if delivery.reminderDate.Before(now.AddDate(0, 0, -30)) {
			delete(s.deliveries, key)
		}
	}
	for id, share := range s.shares {
		if share.Status == model.ShareRevoked && !share.UpdatedAt.After(now.Add(-model.RetentionAfterRevoke)) {
			delete(s.shares, id)
		}
	}
	return nil
}

func (s *MemoryStore) ListSentPartnerNotes(partnerID string) ([]*model.PartnerNote, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]*model.PartnerNote, 0)
	for _, n := range s.partnerNotes {
		if n.PartnerID == partnerID {
			c := *n
			out = append(out, &c)
		}
	}
	return out, nil
}

func (s *MemoryStore) findUserLocked(userID string) *model.User {
	for _, u := range s.users {
		if u.ID == userID {
			return u
		}
	}
	return nil
}

func (s *MemoryStore) liveShareForOwnerLocked(ownerID string) *model.CalendarShare {
	for _, share := range s.shares {
		if share.OwnerID == ownerID && (share.Status == model.ShareOpen || share.Status == model.ShareActive) {
			return share
		}
	}
	return nil
}

func (s *MemoryStore) liveShareForPartnerLocked(partnerID string) *model.CalendarShare {
	for _, share := range s.shares {
		if share.PartnerID == partnerID && (share.Status == model.ShareOpen || share.Status == model.ShareActive) {
			return share
		}
	}
	return nil
}

func (s *MemoryStore) latestShareForPartnerLocked(partnerID string) *model.CalendarShare {
	var latest *model.CalendarShare
	for _, share := range s.shares {
		if share.PartnerID != partnerID {
			continue
		}
		if latest == nil || share.UpdatedAt.After(latest.UpdatedAt) {
			copy := *share
			latest = &copy
		}
	}
	return latest
}

func (s *MemoryStore) unreadNotesLocked(ownerID string) int {
	n := 0
	for _, note := range s.partnerNotes {
		if note.OwnerID == ownerID && note.ReadAt == nil {
			n++
		}
	}
	return n
}

func (s *MemoryStore) shareStateLocked(user *model.User) *model.ShareState {
	role := model.NormalizeRole(user.Role)
	state := &model.ShareState{
		Status:          model.ShareNone,
		CanEditCalendar: role == model.RoleOwner,
	}
	if role == "" {
		return state
	}
	if role == model.RoleOwner {
		live := s.liveShareForOwnerLocked(user.ID)
		if live == nil {
			state.UnreadNotes = s.unreadNotesLocked(user.ID)
			return state
		}
		state.Status = live.Status
		state.InviteCode = live.InviteCode
		state.CanEditCalendar = true
		state.UnreadNotes = s.unreadNotesLocked(user.ID)
		if live.PartnerID != "" {
			if partner := s.findUserLocked(live.PartnerID); partner != nil {
				state.PartnerEmail = partner.Email
				state.PartnerName = partner.Name
			}
		}
		return state
	}

	live := s.liveShareForPartnerLocked(user.ID)
	if live == nil {
		latest := s.latestShareForPartnerLocked(user.ID)
		if latest == nil {
			// Partner who has not joined a calendar yet.
			return state
		}
		state.Status = latest.Status
		if owner := s.findUserLocked(latest.OwnerID); owner != nil {
			state.OwnerName = owner.Name
			state.OwnerEmail = owner.Email
		}
		state.CanEditCalendar = false
		return state
	}
	state.Status = live.Status
	state.CanEditCalendar = false
	if owner := s.findUserLocked(live.OwnerID); owner != nil {
		state.OwnerName = owner.Name
		state.OwnerEmail = owner.Email
	}
	return state
}

func (s *MemoryStore) GetShareState(userID string) (*model.ShareState, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	user := s.findUserLocked(userID)
	if user == nil {
		return nil, fmt.Errorf("user not found")
	}
	return s.shareStateLocked(user), nil
}

func (s *MemoryStore) EnableShare(ownerID string) (*model.ShareState, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	user := s.findUserLocked(ownerID)
	if user == nil {
		return nil, fmt.Errorf("user not found")
	}
	if model.NormalizeRole(user.Role) != model.RoleOwner {
		return nil, fmt.Errorf("only calendar owners can share")
	}
	if live := s.liveShareForOwnerLocked(ownerID); live != nil {
		return s.shareStateLocked(user), nil
	}
	code, err := generateInviteCode()
	if err != nil {
		return nil, err
	}
	now := time.Now().UTC()
	share := &model.CalendarShare{
		ID:         generateID(),
		OwnerID:    ownerID,
		InviteCode: code,
		Status:     model.ShareOpen,
		CreatedAt:  now,
		UpdatedAt:  now,
	}
	s.shares[share.ID] = share
	return s.shareStateLocked(user), nil
}

func (s *MemoryStore) RevokeShare(ownerID string) (*model.ShareState, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	user := s.findUserLocked(ownerID)
	if user == nil {
		return nil, fmt.Errorf("user not found")
	}
	if model.NormalizeRole(user.Role) != model.RoleOwner {
		return nil, fmt.Errorf("only calendar owners can revoke")
	}
	live := s.liveShareForOwnerLocked(ownerID)
	if live == nil {
		return s.shareStateLocked(user), nil
	}
	live.Status = model.ShareRevoked
	live.UpdatedAt = time.Now().UTC()
	return s.shareStateLocked(user), nil
}

func (s *MemoryStore) AcceptShare(partnerID, inviteCode string) (*model.ShareState, error) {
	code := normalizeInviteCode(inviteCode)
	if code == "" {
		return nil, fmt.Errorf("invite code required")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	partner := s.findUserLocked(partnerID)
	if partner == nil {
		return nil, fmt.Errorf("user not found")
	}
	if model.NormalizeRole(partner.Role) == model.RoleOwner {
		return nil, fmt.Errorf("calendar owners cannot join another calendar")
	}
	if live := s.liveShareForPartnerLocked(partnerID); live != nil {
		return nil, fmt.Errorf("already linked to a calendar")
	}
	var target *model.CalendarShare
	for _, share := range s.shares {
		if share.InviteCode == code && share.Status == model.ShareOpen {
			target = share
			break
		}
	}
	if target == nil {
		return nil, fmt.Errorf("invalid or expired invite code")
	}
	if target.OwnerID == partnerID {
		return nil, fmt.Errorf("cannot accept your own invite")
	}
	partner.Role = model.RolePartner
	partner.UpdatedAt = time.Now().UTC()
	target.PartnerID = partnerID
	target.Status = model.ShareActive
	target.UpdatedAt = time.Now().UTC()
	return s.shareStateLocked(partner), nil
}

func (s *MemoryStore) CalendarSubjectID(userID string) (string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	user := s.findUserLocked(userID)
	if user == nil {
		return "", fmt.Errorf("user not found")
	}
	switch model.NormalizeRole(user.Role) {
	case model.RoleOwner:
		return userID, nil
	case "":
		return "", fmt.Errorf("role not chosen")
	}
	live := s.liveShareForPartnerLocked(userID)
	if live == nil || live.Status != model.ShareActive {
		return "", fmt.Errorf("share inactive")
	}
	return live.OwnerID, nil
}

func (s *MemoryStore) ListInboxNotes(ownerID string) ([]*model.PartnerNote, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	user := s.findUserLocked(ownerID)
	if user == nil {
		return nil, fmt.Errorf("user not found")
	}
	out := make([]*model.PartnerNote, 0)
	for _, note := range s.partnerNotes {
		if note.OwnerID != ownerID {
			continue
		}
		copy := *note
		if partner := s.findUserLocked(note.PartnerID); partner != nil {
			copy.FromName = partner.Name
			copy.FromEmail = partner.Email
		}
		out = append(out, &copy)
	}
	// newest first
	for i := 0; i < len(out); i++ {
		for j := i + 1; j < len(out); j++ {
			if out[j].CreatedAt.After(out[i].CreatedAt) {
				out[i], out[j] = out[j], out[i]
			}
		}
	}
	return out, nil
}

func (s *MemoryStore) CreatePartnerNote(partnerID, body string) (*model.PartnerNote, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return nil, fmt.Errorf("note body required")
	}
	if len(body) > 2000 {
		return nil, fmt.Errorf("note too long")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	partner := s.findUserLocked(partnerID)
	if partner == nil {
		return nil, fmt.Errorf("user not found")
	}
	if model.NormalizeRole(partner.Role) != model.RolePartner {
		return nil, fmt.Errorf("only partners can leave inbox notes")
	}
	live := s.liveShareForPartnerLocked(partnerID)
	if live == nil || live.Status != model.ShareActive {
		return nil, fmt.Errorf("share inactive")
	}
	now := time.Now().UTC()
	note := &model.PartnerNote{
		ID:        generateID(),
		OwnerID:   live.OwnerID,
		PartnerID: partnerID,
		Body:      body,
		CreatedAt: now,
		FromName:  partner.Name,
		FromEmail: partner.Email,
	}
	s.partnerNotes[note.ID] = note
	copy := *note
	return &copy, nil
}

func (s *MemoryStore) MarkInboxNoteRead(ownerID, noteID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	note, ok := s.partnerNotes[noteID]
	if !ok || note.OwnerID != ownerID {
		return fmt.Errorf("note not found")
	}
	if note.ReadAt == nil {
		now := time.Now().UTC()
		note.ReadAt = &now
	}
	return nil
}

func (s *MemoryStore) SetRole(userID, role string) (*model.User, error) {
	role = model.NormalizeRole(role)
	if role == "" {
		return nil, fmt.Errorf("role must be owner or partner")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	user := s.findUserLocked(userID)
	if user == nil {
		return nil, fmt.Errorf("user not found")
	}
	if model.NormalizeRole(user.Role) != role {
		if s.liveShareForOwnerLocked(userID) != nil {
			return nil, fmt.Errorf("role locked while a calendar is shared")
		}
		if live := s.liveShareForPartnerLocked(userID); live != nil && live.Status == model.ShareActive {
			return nil, fmt.Errorf("role locked while a calendar is shared")
		}
		user.Role = role
		user.UpdatedAt = time.Now().UTC()
	}
	return sanitizeUser(user), nil
}

func (s *MemoryStore) ListAccountShares(userID string) ([]*model.CalendarShare, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []*model.CalendarShare{}
	for _, sh := range s.shares {
		if sh.OwnerID == userID || sh.PartnerID == userID {
			c := *sh
			c.InviteCode = ""
			out = append(out, &c)
		}
	}
	return out, nil
}
func (s *MemoryStore) ListAccountSubscriptions(userID string) ([]model.ExportPushSubscription, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []model.ExportPushSubscription{}
	for _, sub := range s.subscriptions {
		if sub.UserID == userID {
			out = append(out, model.ExportPushSubscription{Endpoint: sub.Endpoint})
		}
	}
	return out, nil
}

func (s *MemoryStore) ListReceivedPartnerNotes(userID string) ([]*model.PartnerNote, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []*model.PartnerNote{}
	for _, n := range s.partnerNotes {
		if n.OwnerID == userID {
			c := *n
			out = append(out, &c)
		}
	}
	return out, nil
}

func (s *MemoryStore) SetStage(userID, stage string) (*model.User, error) {
	if stage != "cycling" && stage != "perimenopause" && stage != "menopause" {
		return nil, fmt.Errorf("invalid stage")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	u := s.findUserLocked(userID)
	if u == nil {
		return nil, fmt.Errorf("user not found")
	}
	if u.EffectiveRole() != model.RoleOwner {
		return nil, fmt.Errorf("only owners may set stage")
	}
	u.Stage = stage
	u.UpdatedAt = time.Now().UTC()
	return sanitizeUser(u), nil
}
