package store

import (
	"fmt"
	"strings"
	"sync"
	"time"

	"217/backend/internal/model"
	"golang.org/x/crypto/bcrypt"
)

type memoryDelivery struct {
	sent        bool
	claimedAt   time.Time
	nextAttempt time.Time
	attempts    int
}

type memorySession struct {
	UserID    string
	CreatedAt time.Time
	ExpiresAt time.Time
	UserAgent string
	IPAddress string
}

type memoryOAuthAttempt struct {
	Nonce        string
	CodeVerifier string
	BindingHash  string
	ExpiresAt    time.Time
}

type MemoryStore struct {
	mu             sync.RWMutex
	users          map[string]*model.User
	entries        map[string]*model.Entry
	preferences    map[string]*model.ReminderPreference
	subscriptions  map[string]*model.PushSubscription
	deliveries     map[string]memoryDelivery
	workosSubjects map[string]string // subject -> userID
	oauthAttempts  map[string]memoryOAuthAttempt
	sessions       map[string]memorySession // keyed by hashed session id (sha256 hex)
	shares         map[string]*model.CalendarShare
	partnerNotes   map[string]*model.PartnerNote
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		users:          make(map[string]*model.User),
		entries:        make(map[string]*model.Entry),
		preferences:    make(map[string]*model.ReminderPreference),
		subscriptions:  make(map[string]*model.PushSubscription),
		deliveries:     make(map[string]memoryDelivery),
		workosSubjects: make(map[string]string),
		oauthAttempts:  make(map[string]memoryOAuthAttempt),
		sessions:       make(map[string]memorySession),
		shares:         make(map[string]*model.CalendarShare),
		partnerNotes:   make(map[string]*model.PartnerNote),
	}
}

func (s *MemoryStore) CreateUser(email, name, password string) (*model.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	for _, u := range s.users {
		if u.Email == email {
			return nil, fmt.Errorf("email already registered")
		}
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hashing password: %w", err)
	}

	now := time.Now().UTC()
	user := &model.User{
		ID:           generateID(),
		Email:        email,
		Name:         name,
		Role:         model.RoleOwner,
		PasswordHash: string(hash),
		APIKey:       generateAPIKey(),
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	s.users[user.APIKey] = user
	return user, nil
}

func (s *MemoryStore) GetUserByAPIKey(apiKey string) (*model.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	u, ok := s.users[apiKey]
	if !ok {
		return nil, fmt.Errorf("invalid api key")
	}
	return u, nil
}

func (s *MemoryStore) GetUserByEmail(email string) (*model.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, u := range s.users {
		if u.Email == email {
			return u, nil
		}
	}
	return nil, fmt.Errorf("user not found")
}

func (s *MemoryStore) VerifyPassword(email, password string) (*model.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, u := range s.users {
		if u.Email == email {
			if err := bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(password)); err != nil {
				return nil, fmt.Errorf("invalid password")
			}
			user := *u
			user.PasswordHash = ""
			return &user, nil
		}
	}
	return nil, fmt.Errorf("user not found")
}

func entryKey(userID, date string) string {
	return userID + ":" + date
}

func (s *MemoryStore) GetEntry(userID, date string) (*model.Entry, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	e, ok := s.entries[entryKey(userID, date)]
	if !ok {
		return nil, fmt.Errorf("entry not found")
	}
	return e, nil
}

func (s *MemoryStore) ListEntries(userID string, year, month int) ([]*model.Entry, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	userPrefix := userID + ":"
	datePrefix := fmt.Sprintf("%04d-%02d", year, month)
	var result []*model.Entry
	for k, e := range s.entries {
		if strings.HasPrefix(k, userPrefix) && strings.HasPrefix(k[len(userPrefix):], datePrefix) {
			result = append(result, e)
		}
	}
	if result == nil {
		result = []*model.Entry{}
	}
	return result, nil
}

func (s *MemoryStore) UpsertEntry(userID, date string, req model.UpsertRequest) (*model.Entry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	key := entryKey(userID, date)
	now := time.Now().UTC()
	if existing, ok := s.entries[key]; ok {
		existing.Taken = req.Taken
		existing.Notes = req.Notes
		existing.Heart = req.Heart
		existing.UpdatedAt = now
		return existing, nil
	}

	entry := &model.Entry{
		ID:        generateID(),
		UserID:    userID,
		Date:      date,
		Taken:     req.Taken,
		Notes:     req.Notes,
		Heart:     req.Heart,
		CreatedAt: now,
		UpdatedAt: now,
	}
	s.entries[key] = entry
	return entry, nil
}

func (s *MemoryStore) DeleteEntry(userID, date string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := entryKey(userID, date)
	if _, ok := s.entries[key]; !ok {
		return fmt.Errorf("entry not found")
	}
	delete(s.entries, key)
	return nil
}

func (s *MemoryStore) GetStats(userID string, year, month int) (*model.Stats, error) {
	entries, _ := s.ListEntries(userID, year, month)
	now := time.Now().UTC()

	firstDay := time.Date(year, time.Month(month), 1, 0, 0, 0, 0, time.UTC)
	lastDay := firstDay.AddDate(0, 1, -1)
	totalDays := lastDay.Day()

	takenDays := 0
	for _, e := range entries {
		if e.Taken {
			takenDays++
		}
	}
	missedDays := totalDays - takenDays

	streak := 0
	current := now
	for current.Month() == time.Month(month) && current.Year() == year && !current.Before(firstDay) {
		dateStr := current.Format("2006-01-02")
		if e, ok := s.entries[entryKey(userID, dateStr)]; ok && e.Taken {
			streak++
			current = current.AddDate(0, 0, -1)
		} else {
			break
		}
	}

	return &model.Stats{
		Year:       year,
		Month:      month,
		TotalDays:  totalDays,
		TakenDays:  takenDays,
		MissedDays: missedDays,
		Streak:     streak,
	}, nil
}

func (s *MemoryStore) ChangePassword(userID, oldPassword, newPassword string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	for _, u := range s.users {
		if u.ID == userID {
			if err := bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(oldPassword)); err != nil {
				return fmt.Errorf("invalid current password")
			}
			hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
			if err != nil {
				return fmt.Errorf("hashing password: %w", err)
			}
			u.PasswordHash = string(hash)
			u.UpdatedAt = time.Now().UTC()
			return nil
		}
	}
	return fmt.Errorf("user not found")
}

func (s *MemoryStore) LinkWorkOSIdentity(subject, verifiedEmail, name string, authoritative bool) (*model.User, error) {
	normalizedEmail := normalizeEmail(verifiedEmail)
	s.mu.Lock()
	defer s.mu.Unlock()

	if userID, ok := s.workosSubjects[subject]; ok {
		for _, user := range s.users {
			if user.ID == userID {
				return sanitizeUser(user), nil
			}
		}
		delete(s.workosSubjects, subject)
	}

	var matchingUser *model.User
	matchCount := 0
	for _, user := range s.users {
		if normalizeEmail(user.Email) == normalizedEmail {
			matchingUser = user
			matchCount++
		}
	}
	if matchCount > 1 {
		return nil, fmt.Errorf("ambiguous normalized email: multiple existing accounts require operator resolution")
	}
	if matchingUser != nil {
		if !authoritative {
			return nil, fmt.Errorf("legacy account requires independent ownership proof")
		}
		for _, userID := range s.workosSubjects {
			if userID == matchingUser.ID {
				return nil, fmt.Errorf("account already linked to another workos subject")
			}
		}
		s.workosSubjects[subject] = matchingUser.ID
		return sanitizeUser(matchingUser), nil
	}

	if name == "" {
		name = normalizedEmail
	}
	now := time.Now().UTC()
	user := &model.User{
		ID:        generateID(),
		Email:     normalizedEmail,
		Name:      name,
		Role:      model.RoleOwner,
		APIKey:    generateAPIKey(),
		CreatedAt: now,
		UpdatedAt: now,
	}
	s.users[user.APIKey] = user
	s.workosSubjects[subject] = user.ID
	return sanitizeUser(user), nil
}

func (s *MemoryStore) CreateOAuthAttempt(state, binding, codeVerifier, nonce string, expiresAt time.Time) error {
	hash := hashString(state)
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now().UTC()
	for key, attempt := range s.oauthAttempts {
		if now.After(attempt.ExpiresAt) {
			delete(s.oauthAttempts, key)
		}
	}
	s.oauthAttempts[hash] = memoryOAuthAttempt{Nonce: nonce, CodeVerifier: codeVerifier, BindingHash: hashString(binding), ExpiresAt: expiresAt}
	return nil
}

func (s *MemoryStore) ConsumeOAuthAttempt(state, binding string) (OAuthAttempt, error) {
	hash := hashString(state)
	s.mu.Lock()
	defer s.mu.Unlock()
	attempt, ok := s.oauthAttempts[hash]
	if !ok {
		return OAuthAttempt{}, fmt.Errorf("oauth state not found")
	}
	if !attempt.ExpiresAt.IsZero() && time.Now().UTC().After(attempt.ExpiresAt) {
		delete(s.oauthAttempts, hash)
		return OAuthAttempt{}, fmt.Errorf("oauth state expired")
	}
	if attempt.BindingHash != hashString(binding) {
		return OAuthAttempt{}, fmt.Errorf("oauth browser binding mismatch")
	}
	delete(s.oauthAttempts, hash)
	return OAuthAttempt{CodeVerifier: attempt.CodeVerifier, Nonce: attempt.Nonce}, nil
}

func (s *MemoryStore) GetReminderPreference(userID string) (*model.ReminderPreference, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	preference := model.ReminderPreference{Time: model.DefaultReminderTime, Timezone: model.DefaultReminderTimezone}
	if existing, ok := s.preferences[userID]; ok {
		preference = *existing
	}
	for _, subscription := range s.subscriptions {
		if subscription.UserID == userID {
			preference.SubscriptionCount++
		}
	}
	preference.Deliverable = preference.Enabled && preference.SubscriptionCount > 0
	return &preference, nil
}

func (s *MemoryStore) UpsertReminderPreference(userID string, preference model.ReminderPreference) (*model.ReminderPreference, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now().UTC()
	if existing, ok := s.preferences[userID]; ok {
		preference.CreatedAt = existing.CreatedAt
	} else {
		preference.CreatedAt = now
	}
	preference.UpdatedAt = now
	preference.SubscriptionCount = 0
	preference.Deliverable = false
	for _, subscription := range s.subscriptions {
		if subscription.UserID == userID {
			preference.SubscriptionCount++
		}
	}
	preference.Deliverable = preference.Enabled && preference.SubscriptionCount > 0
	stored := preference
	stored.SubscriptionCount = 0
	stored.Deliverable = false
	s.preferences[userID] = &stored
	copy := preference
	return &copy, nil
}

func (s *MemoryStore) SavePushSubscription(userID string, request model.PushSubscriptionRequest) (*model.PushSubscription, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if existing, ok := s.subscriptions[request.Endpoint]; ok && existing.UserID != userID {
		return nil, fmt.Errorf("subscription belongs to another user")
	}
	now := time.Now().UTC()
	subscription, ok := s.subscriptions[request.Endpoint]
	if !ok {
		count := 0
		for _, existing := range s.subscriptions {
			if existing.UserID == userID {
				count++
			}
		}
		if count >= model.MaxPushSubscriptions {
			return nil, fmt.Errorf("push subscription limit reached")
		}
		subscription = &model.PushSubscription{ID: generateID(), UserID: userID, Endpoint: request.Endpoint, CreatedAt: now}
		s.subscriptions[request.Endpoint] = subscription
	}
	subscription.P256DH = request.Keys.P256DH
	subscription.Auth = request.Keys.Auth
	subscription.UpdatedAt = now
	copy := *subscription
	return &copy, nil
}

func (s *MemoryStore) DeletePushSubscription(userID, endpoint string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if subscription, ok := s.subscriptions[endpoint]; ok && subscription.UserID == userID {
		delete(s.subscriptions, endpoint)
	}
	return nil
}

func (s *MemoryStore) CountPushSubscriptions(userID string) (int, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	count := 0
	for _, subscription := range s.subscriptions {
		if subscription.UserID == userID {
			count++
		}
	}
	return count, nil
}

func (s *MemoryStore) ListReminderTargets() ([]model.ReminderTarget, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := []model.ReminderTarget{}
	for _, subscription := range s.subscriptions {
		preference, ok := s.preferences[subscription.UserID]
		if !ok || !preference.Enabled {
			continue
		}
		name := ""
		for _, user := range s.users {
			if user.ID == subscription.UserID {
				name = user.Name
				break
			}
		}
		result = append(result, model.ReminderTarget{
			SubscriptionID: subscription.ID, UserID: subscription.UserID, UserName: name,
			Endpoint: subscription.Endpoint, P256DH: subscription.P256DH, Auth: subscription.Auth,
			Time: preference.Time, Timezone: preference.Timezone,
		})
	}
	return result, nil
}

func deliveryKey(subscriptionID string, reminderDate time.Time) string {
	return subscriptionID + ":" + reminderDate.Format("2006-01-02")
}

func (s *MemoryStore) ClaimReminderDelivery(subscriptionID string, reminderDate, now time.Time) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := deliveryKey(subscriptionID, reminderDate)
	delivery, exists := s.deliveries[key]
	if exists {
		if delivery.sent || now.Before(delivery.nextAttempt) || now.Sub(delivery.claimedAt) < 5*time.Minute {
			return false, nil
		}
	}
	delivery.claimedAt = now
	delivery.attempts++
	s.deliveries[key] = delivery
	return true, nil
}

func (s *MemoryStore) FinishReminderDelivery(subscriptionID string, reminderDate time.Time, sent bool, now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := deliveryKey(subscriptionID, reminderDate)
	delivery, ok := s.deliveries[key]
	if !ok {
		return nil
	}
	if sent {
		delivery.sent = true
		delivery.nextAttempt = time.Time{}
	} else {
		delay := time.Minute << min(delivery.attempts-1, 5)
		delivery.claimedAt = time.Time{}
		delivery.nextAttempt = now.Add(delay)
	}
	s.deliveries[key] = delivery
	return nil
}

func (s *MemoryStore) CreateSession(userID, sessionID string, expiresAt time.Time, userAgent, ip string) error {
	hash := hashString(sessionID)
	s.mu.Lock()
	defer s.mu.Unlock()
	for key, session := range s.sessions {
		if time.Now().UTC().After(session.ExpiresAt) {
			delete(s.sessions, key)
		}
	}
	s.sessions[hash] = memorySession{UserID: userID, CreatedAt: time.Now().UTC(), ExpiresAt: expiresAt, UserAgent: userAgent, IPAddress: ip}
	return nil
}

func (s *MemoryStore) GetUserBySession(sessionID string) (*model.User, error) {
	hash := hashString(sessionID)
	s.mu.Lock()
	defer s.mu.Unlock()
	sess, ok := s.sessions[hash]
	if !ok {
		return nil, fmt.Errorf("session not found")
	}
	if !sess.ExpiresAt.IsZero() && time.Now().UTC().After(sess.ExpiresAt) {
		delete(s.sessions, hash)
		return nil, fmt.Errorf("session expired")
	}
	for _, u := range s.users {
		if u.ID == sess.UserID {
			return sanitizeUser(u), nil
		}
	}
	return nil, fmt.Errorf("user not found")
}

func (s *MemoryStore) DeleteSession(sessionID string) error {
	hash := hashString(sessionID)
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.sessions, hash)
	return nil
}

func (s *MemoryStore) DeleteAllSessionsForUser(userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for k, v := range s.sessions {
		if v.UserID == userID {
			delete(s.sessions, k)
		}
	}
	return nil
}

func (s *MemoryStore) Close() error { return nil }
