package store

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"217/backend/internal/model"
	"golang.org/x/crypto/bcrypt"

	_ "github.com/jackc/pgx/v5/stdlib"
)

type PGStore struct {
	db *sql.DB
}

func NewPGStore(databaseURL string) (*PGStore, error) {
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("opening database: %w", err)
	}
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("pinging database: %w", err)
	}

	return &PGStore{db: db}, nil
}

func (s *PGStore) CreateUser(email, name, password string) (*model.User, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hashing password: %w", err)
	}

	apiKey := generateAPIKey()
	user := &model.User{}
	err = s.db.QueryRow(
		`INSERT INTO users (email, name, api_key, password_hash) VALUES ($1, $2, $3, $4)
		 RETURNING id, email, name, api_key, created_at, updated_at`,
		email, name, apiKey, string(hash),
	).Scan(&user.ID, &user.Email, &user.Name, &user.APIKey, &user.CreatedAt, &user.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("creating user: %w", err)
	}
	return user, nil
}

func (s *PGStore) GetUserByAPIKey(apiKey string) (*model.User, error) {
	user := &model.User{}
	err := s.db.QueryRow(
		`SELECT id, email, name, api_key, created_at, updated_at FROM users WHERE api_key = $1`,
		apiKey,
	).Scan(&user.ID, &user.Email, &user.Name, &user.APIKey, &user.CreatedAt, &user.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("invalid api key")
	}
	if err != nil {
		return nil, fmt.Errorf("getting user: %w", err)
	}
	return user, nil
}

func (s *PGStore) GetUserByEmail(email string) (*model.User, error) {
	user := &model.User{}
	err := s.db.QueryRow(
		`SELECT id, email, name, api_key, password_hash, created_at, updated_at FROM users WHERE email = $1`,
		email,
	).Scan(&user.ID, &user.Email, &user.Name, &user.APIKey, &user.PasswordHash, &user.CreatedAt, &user.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("user not found")
	}
	if err != nil {
		return nil, fmt.Errorf("getting user: %w", err)
	}
	return user, nil
}

func (s *PGStore) VerifyPassword(email, password string) (*model.User, error) {
	user, err := s.GetUserByEmail(email)
	if err != nil {
		return nil, err
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return nil, fmt.Errorf("invalid password")
	}

	user.PasswordHash = ""
	return user, nil
}

func formatDate(t time.Time) string {
	return t.Format("2006-01-02")
}

func (s *PGStore) GetEntry(userID, date string) (*model.Entry, error) {
	e := &model.Entry{}
	var dateVal time.Time
	err := s.db.QueryRow(
		`SELECT id, user_id, date, taken, notes, created_at, updated_at
		 FROM entries WHERE user_id = $1 AND date = $2`,
		userID, date,
	).Scan(&e.ID, &e.UserID, &dateVal, &e.Taken, &e.Notes, &e.CreatedAt, &e.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("entry not found")
	}
	if err != nil {
		return nil, fmt.Errorf("getting entry: %w", err)
	}
	e.Date = dateVal.Format("2006-01-02")
	return e, nil
}

func (s *PGStore) ListEntries(userID string, year, month int) ([]*model.Entry, error) {
	firstDay := fmt.Sprintf("%04d-%02d-01", year, month)
	lastDay := time.Date(year, time.Month(month)+1, 0, 0, 0, 0, 0, time.UTC).Format("2006-01-02")

	rows, err := s.db.Query(
		`SELECT id, user_id, date, taken, notes, created_at, updated_at
		 FROM entries WHERE user_id = $1 AND date >= $2 AND date <= $3
		 ORDER BY date ASC`,
		userID, firstDay, lastDay,
	)
	if err != nil {
		return nil, fmt.Errorf("listing entries: %w", err)
	}
	defer rows.Close()

	var result []*model.Entry
	for rows.Next() {
		e := &model.Entry{}
		var dateVal time.Time
		if err := rows.Scan(&e.ID, &e.UserID, &dateVal, &e.Taken, &e.Notes, &e.CreatedAt, &e.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scanning entry: %w", err)
		}
		e.Date = dateVal.Format("2006-01-02")
		result = append(result, e)
	}
	if result == nil {
		result = []*model.Entry{}
	}
	return result, nil
}

func (s *PGStore) UpsertEntry(userID, date string, req model.UpsertRequest) (*model.Entry, error) {
	e := &model.Entry{}
	var dateVal time.Time
	err := s.db.QueryRow(
		`INSERT INTO entries (user_id, date, taken, notes)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (user_id, date) DO UPDATE SET
		   taken = EXCLUDED.taken,
		   notes = EXCLUDED.notes,
		   updated_at = NOW()
		 RETURNING id, user_id, date, taken, notes, created_at, updated_at`,
		userID, date, req.Taken, req.Notes,
	).Scan(&e.ID, &e.UserID, &dateVal, &e.Taken, &e.Notes, &e.CreatedAt, &e.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("upserting entry: %w", err)
	}
	e.Date = formatDate(dateVal)
	return e, nil
}

func (s *PGStore) DeleteEntry(userID, date string) error {
	res, err := s.db.Exec(
		`DELETE FROM entries WHERE user_id = $1 AND date = $2`,
		userID, date,
	)
	if err != nil {
		return fmt.Errorf("deleting entry: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("deleting entry rows: %w", err)
	}
	if n == 0 {
		return fmt.Errorf("entry not found")
	}
	return nil
}

func (s *PGStore) GetStats(userID string, year, month int) (*model.Stats, error) {
	firstDay := fmt.Sprintf("%04d-%02d-01", year, month)
	lastDay := time.Date(year, time.Month(month)+1, 0, 0, 0, 0, 0, time.UTC).Format("2006-01-02")

	var totalEntries int
	var takenEntries int
	if err := s.db.QueryRow(
		`SELECT COUNT(*), COALESCE(SUM(CASE WHEN taken THEN 1 ELSE 0 END), 0)
		 FROM entries WHERE user_id = $1 AND date >= $2 AND date <= $3`,
		userID, firstDay, lastDay,
	).Scan(&totalEntries, &takenEntries); err != nil {
		return nil, fmt.Errorf("getting stats: %w", err)
	}

	totalDays := time.Date(year, time.Month(month)+1, 0, 0, 0, 0, 0, time.UTC).Day()
	missedDays := totalDays - takenEntries

	var streak int
	// count consecutive days going backwards from today (within this month)
	currentDate := time.Now().UTC()
	for currentDate.Month() == time.Month(month) && currentDate.Year() == year {
		var taken bool
		err := s.db.QueryRow(
			`SELECT taken FROM entries WHERE user_id = $1 AND date = $2`,
			userID, currentDate.Format("2006-01-02"),
		).Scan(&taken)
		if err != nil || !taken {
			break
		}
		streak++
		currentDate = currentDate.AddDate(0, 0, -1)
	}

	return &model.Stats{
		Year:       year,
		Month:      month,
		TotalDays:  totalDays,
		TakenDays:  takenEntries,
		MissedDays: missedDays,
		Streak:     streak,
	}, nil
}

func (s *PGStore) ChangePassword(userID, oldPassword, newPassword string) error {
	var hash string
	err := s.db.QueryRow(
		`SELECT password_hash FROM users WHERE id = $1`, userID,
	).Scan(&hash)
	if err == sql.ErrNoRows {
		return fmt.Errorf("user not found")
	}
	if err != nil {
		return fmt.Errorf("getting user: %w", err)
	}

	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(oldPassword)); err != nil {
		return fmt.Errorf("invalid current password")
	}

	newHash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hashing password: %w", err)
	}

	_, err = s.db.Exec(`UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2`, string(newHash), userID)
	if err != nil {
		return fmt.Errorf("updating password: %w", err)
	}
	return nil
}

func (s *PGStore) LinkWorkOSIdentity(subject, verifiedEmail, name string, authoritative bool) (*model.User, error) {
	normalizedEmail := normalizeEmail(verifiedEmail)
	tx, err := s.db.BeginTx(context.Background(), &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return nil, fmt.Errorf("beginning workos link transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()
	// Serialize both subject and normalized-email decisions so concurrent first
	// logins cannot create duplicate users or move an identity between users.
	if _, err := tx.Exec(`SELECT pg_advisory_xact_lock(hashtextextended($1, 217))`, subject); err != nil {
		return nil, fmt.Errorf("locking workos subject: %w", err)
	}
	if _, err := tx.Exec(`SELECT pg_advisory_xact_lock(hashtextextended($1, 218))`, normalizedEmail); err != nil {
		return nil, fmt.Errorf("locking workos email: %w", err)
	}

	user := &model.User{}
	err = tx.QueryRow(`SELECT u.id, u.email, u.name, u.api_key, u.password_hash, u.created_at, u.updated_at
		FROM workos_identities gi
		JOIN users u ON u.id = gi.user_id
		WHERE gi.subject = $1`, subject).
		Scan(&user.ID, &user.Email, &user.Name, &user.APIKey, &user.PasswordHash, &user.CreatedAt, &user.UpdatedAt)
	if err == nil {
		if err := tx.Commit(); err != nil {
			return nil, fmt.Errorf("committing workos identity lookup: %w", err)
		}
		return sanitizeUser(user), nil
	}
	if err != nil && err != sql.ErrNoRows {
		return nil, fmt.Errorf("getting workos identity: %w", err)
	}

	var normalizedMatches int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM users WHERE LOWER(email) = $1`, normalizedEmail).Scan(&normalizedMatches); err != nil {
		return nil, fmt.Errorf("counting normalized email matches: %w", err)
	}
	if normalizedMatches > 1 {
		return nil, fmt.Errorf("ambiguous normalized email: multiple existing accounts require operator resolution")
	}

	if normalizedMatches == 1 {
		if !authoritative {
			return nil, fmt.Errorf("legacy account requires independent ownership proof")
		}
		var alreadyLinked bool
		if err := tx.QueryRow(`SELECT EXISTS (SELECT 1 FROM workos_identities gi JOIN users u ON u.id = gi.user_id WHERE LOWER(u.email) = $1)`, normalizedEmail).Scan(&alreadyLinked); err != nil {
			return nil, fmt.Errorf("checking existing workos link: %w", err)
		}
		if alreadyLinked {
			return nil, fmt.Errorf("account already linked to another workos subject")
		}
	}

	err = tx.QueryRow(`SELECT id, email, name, api_key, password_hash, created_at, updated_at
		FROM users WHERE LOWER(email) = $1 FOR UPDATE`, normalizedEmail).
		Scan(&user.ID, &user.Email, &user.Name, &user.APIKey, &user.PasswordHash, &user.CreatedAt, &user.UpdatedAt)
	if err == sql.ErrNoRows {
		if name == "" {
			name = normalizedEmail
		}
		err = tx.QueryRow(`INSERT INTO users (email, name, api_key, password_hash)
			VALUES ($1, $2, $3, '') RETURNING id, email, name, api_key, password_hash, created_at, updated_at`,
			normalizedEmail, name, generateAPIKey()).
			Scan(&user.ID, &user.Email, &user.Name, &user.APIKey, &user.PasswordHash, &user.CreatedAt, &user.UpdatedAt)
	}
	if err != nil {
		return nil, fmt.Errorf("finding user for workos identity: %w", err)
	}

	_, err = tx.Exec(`INSERT INTO workos_identities (subject, user_id, email_normalized)
		VALUES ($1, $2, $3)`,
		subject, user.ID, normalizedEmail)
	if err != nil {
		return nil, fmt.Errorf("linking workos identity: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("committing workos identity link: %w", err)
	}
	return sanitizeUser(user), nil
}

func (s *PGStore) GetReminderPreference(userID string) (*model.ReminderPreference, error) {
	preference := &model.ReminderPreference{Time: model.DefaultReminderTime, Timezone: model.DefaultReminderTimezone}
	err := s.db.QueryRow(`SELECT enabled, reminder_time, timezone, created_at, updated_at
		FROM reminder_preferences WHERE user_id = $1`, userID).
		Scan(&preference.Enabled, &preference.Time, &preference.Timezone, &preference.CreatedAt, &preference.UpdatedAt)
	if err != nil && err != sql.ErrNoRows {
		return nil, fmt.Errorf("getting reminder preference: %w", err)
	}
	count, err := s.CountPushSubscriptions(userID)
	if err != nil {
		return nil, err
	}
	preference.SubscriptionCount = count
	preference.Deliverable = preference.Enabled && count > 0
	return preference, nil
}

func (s *PGStore) UpsertReminderPreference(userID string, preference model.ReminderPreference) (*model.ReminderPreference, error) {
	result := &model.ReminderPreference{}
	err := s.db.QueryRow(`INSERT INTO reminder_preferences (user_id, enabled, reminder_time, timezone)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id) DO UPDATE SET enabled = EXCLUDED.enabled,
			reminder_time = EXCLUDED.reminder_time, timezone = EXCLUDED.timezone, updated_at = NOW()
		RETURNING enabled, reminder_time, timezone, created_at, updated_at`,
		userID, preference.Enabled, preference.Time, preference.Timezone).
		Scan(&result.Enabled, &result.Time, &result.Timezone, &result.CreatedAt, &result.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("upserting reminder preference: %w", err)
	}
	count, err := s.CountPushSubscriptions(userID)
	if err != nil {
		return nil, err
	}
	result.SubscriptionCount = count
	result.Deliverable = result.Enabled && count > 0
	return result, nil
}

func (s *PGStore) SavePushSubscription(userID string, request model.PushSubscriptionRequest) (*model.PushSubscription, error) {
	var owner string
	err := s.db.QueryRow(`SELECT user_id FROM push_subscriptions WHERE endpoint = $1`, request.Endpoint).Scan(&owner)
	if err != nil && err != sql.ErrNoRows {
		return nil, fmt.Errorf("checking push subscription: %w", err)
	}
	if err == nil && owner != userID {
		return nil, fmt.Errorf("subscription belongs to another user")
	}
	if err == sql.ErrNoRows {
		count, countErr := s.CountPushSubscriptions(userID)
		if countErr != nil {
			return nil, countErr
		}
		if count >= model.MaxPushSubscriptions {
			return nil, fmt.Errorf("push subscription limit reached")
		}
	}
	subscription := &model.PushSubscription{}
	err = s.db.QueryRow(`INSERT INTO push_subscriptions (user_id, endpoint, p256dh, auth)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (endpoint) DO UPDATE SET p256dh = EXCLUDED.p256dh, auth = EXCLUDED.auth, updated_at = NOW()
		WHERE push_subscriptions.user_id = EXCLUDED.user_id
		RETURNING id, user_id, endpoint, p256dh, auth, created_at, updated_at`,
		userID, request.Endpoint, request.Keys.P256DH, request.Keys.Auth).
		Scan(&subscription.ID, &subscription.UserID, &subscription.Endpoint, &subscription.P256DH,
			&subscription.Auth, &subscription.CreatedAt, &subscription.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("subscription belongs to another user")
	}
	if err != nil {
		return nil, fmt.Errorf("saving push subscription: %w", err)
	}
	return subscription, nil
}

func (s *PGStore) DeletePushSubscription(userID, endpoint string) error {
	_, err := s.db.Exec(`DELETE FROM push_subscriptions WHERE user_id = $1 AND endpoint = $2`, userID, endpoint)
	if err != nil {
		return fmt.Errorf("deleting push subscription: %w", err)
	}
	return nil
}

func (s *PGStore) CountPushSubscriptions(userID string) (int, error) {
	var count int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM push_subscriptions WHERE user_id = $1`, userID).Scan(&count); err != nil {
		return 0, fmt.Errorf("counting push subscriptions: %w", err)
	}
	return count, nil
}

func (s *PGStore) ListReminderTargets() ([]model.ReminderTarget, error) {
	rows, err := s.db.Query(`SELECT ps.id, ps.user_id, u.name, ps.endpoint, ps.p256dh, ps.auth,
		rp.reminder_time, rp.timezone
		FROM push_subscriptions ps
		JOIN users u ON u.id = ps.user_id
		JOIN reminder_preferences rp ON rp.user_id = ps.user_id
		WHERE rp.enabled = TRUE`)
	if err != nil {
		return nil, fmt.Errorf("listing reminder targets: %w", err)
	}
	defer rows.Close()
	result := []model.ReminderTarget{}
	for rows.Next() {
		var target model.ReminderTarget
		if err := rows.Scan(&target.SubscriptionID, &target.UserID, &target.UserName, &target.Endpoint,
			&target.P256DH, &target.Auth, &target.Time, &target.Timezone); err != nil {
			return nil, fmt.Errorf("scanning reminder target: %w", err)
		}
		result = append(result, target)
	}
	return result, rows.Err()
}

func (s *PGStore) ClaimReminderDelivery(subscriptionID string, reminderDate, now time.Time) (bool, error) {
	var claimed string
	err := s.db.QueryRow(`INSERT INTO reminder_deliveries
		(subscription_id, reminder_date, status, claimed_at, attempts, next_attempt_at)
		VALUES ($1, $2, 'sending', $3, 1, $3)
		ON CONFLICT (subscription_id, reminder_date) DO UPDATE
		SET status = 'sending', claimed_at = $3, attempts = reminder_deliveries.attempts + 1
		WHERE reminder_deliveries.status <> 'sent'
		  AND reminder_deliveries.next_attempt_at <= $3
		  AND (reminder_deliveries.claimed_at IS NULL OR reminder_deliveries.claimed_at <= $3 - INTERVAL '5 minutes')
		RETURNING subscription_id::text`, subscriptionID, reminderDate.Format("2006-01-02"), now.UTC()).Scan(&claimed)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("claiming reminder delivery: %w", err)
	}
	return true, nil
}

func (s *PGStore) FinishReminderDelivery(subscriptionID string, reminderDate time.Time, sent bool, now time.Time) error {
	if sent {
		_, err := s.db.Exec(`UPDATE reminder_deliveries SET status = 'sent', sent_at = $3, claimed_at = NULL
			WHERE subscription_id = $1 AND reminder_date = $2`, subscriptionID, reminderDate.Format("2006-01-02"), now.UTC())
		return err
	}
	_, err := s.db.Exec(`UPDATE reminder_deliveries
		SET status = 'retry', claimed_at = NULL,
			next_attempt_at = $3 + (INTERVAL '1 minute' * LEAST(POWER(2, attempts - 1), 32))
		WHERE subscription_id = $1 AND reminder_date = $2 AND status = 'sending'`,
		subscriptionID, reminderDate.Format("2006-01-02"), now.UTC())
	return err
}

func (s *PGStore) CreateOAuthAttempt(state, binding, codeVerifier, nonce string, expiresAt time.Time) error {
	hash := hashString(state)
	_, _ = s.db.Exec(`DELETE FROM oauth_attempts WHERE expires_at <= NOW() OR consumed_at IS NOT NULL`)
	_, err := s.db.Exec(`INSERT INTO oauth_attempts (state_hash, binding_hash, code_verifier, nonce, expires_at, consumed_at)
		VALUES ($1, $2, $3, $4, $5, NULL)`, hash, hashString(binding), codeVerifier, nonce, expiresAt)
	if err != nil {
		return fmt.Errorf("creating oauth attempt: %w", err)
	}
	return nil
}

func (s *PGStore) ConsumeOAuthAttempt(state, binding string) (OAuthAttempt, error) {
	hash := hashString(state)
	tx, err := s.db.Begin()
	if err != nil {
		return OAuthAttempt{}, fmt.Errorf("beginning oauth attempt transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback()
	}()

	var codeVerifier, nonce string
	var expiresAt time.Time
	var consumedAt sql.NullTime
	var bindingHash string
	err = tx.QueryRow(`SELECT code_verifier, nonce, binding_hash, expires_at, consumed_at FROM oauth_attempts WHERE state_hash = $1 FOR UPDATE`, hash).
		Scan(&codeVerifier, &nonce, &bindingHash, &expiresAt, &consumedAt)
	if err == sql.ErrNoRows {
		return OAuthAttempt{}, fmt.Errorf("oauth state not found")
	}
	if err != nil {
		return OAuthAttempt{}, fmt.Errorf("getting oauth attempt: %w", err)
	}
	if time.Now().UTC().After(expiresAt) {
		_, _ = tx.Exec(`DELETE FROM oauth_attempts WHERE state_hash = $1`, hash)
		return OAuthAttempt{}, fmt.Errorf("oauth state expired")
	}
	if consumedAt.Valid {
		return OAuthAttempt{}, fmt.Errorf("oauth state already used")
	}
	if bindingHash != hashString(binding) {
		return OAuthAttempt{}, fmt.Errorf("oauth browser binding mismatch")
	}
	if _, err := tx.Exec(`UPDATE oauth_attempts SET consumed_at = NOW() WHERE state_hash = $1`, hash); err != nil {
		return OAuthAttempt{}, fmt.Errorf("consuming oauth attempt: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return OAuthAttempt{}, fmt.Errorf("committing oauth attempt: %w", err)
	}
	return OAuthAttempt{CodeVerifier: codeVerifier, Nonce: nonce}, nil
}

func (s *PGStore) CreateSession(userID, sessionID string, expiresAt time.Time, userAgent, ip string) error {
	hash := hashString(sessionID)
	_, _ = s.db.Exec(`DELETE FROM sessions WHERE expires_at <= NOW()`)
	_, err := s.db.Exec(`INSERT INTO sessions (id, user_id, created_at, expires_at, user_agent, ip_address)
		VALUES ($1, $2, NOW(), $3, $4, $5)
		ON CONFLICT (id) DO UPDATE SET user_id = EXCLUDED.user_id, expires_at = EXCLUDED.expires_at, user_agent = EXCLUDED.user_agent, ip_address = EXCLUDED.ip_address, created_at = NOW()`,
		hash, userID, expiresAt, userAgent, ip)
	if err != nil {
		return fmt.Errorf("creating session: %w", err)
	}
	return nil
}

func (s *PGStore) GetUserBySession(sessionID string) (*model.User, error) {
	hash := hashString(sessionID)
	user := &model.User{}
	var expires sql.NullTime
	err := s.db.QueryRow(`SELECT u.id, u.email, u.name, u.api_key, u.password_hash, u.created_at, u.updated_at, s.expires_at
		FROM sessions s JOIN users u ON u.id = s.user_id
		WHERE s.id = $1`, hash).Scan(&user.ID, &user.Email, &user.Name, &user.APIKey, &user.PasswordHash, &user.CreatedAt, &user.UpdatedAt, &expires)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("session not found")
	}
	if err != nil {
		return nil, fmt.Errorf("getting user by session: %w", err)
	}
	if expires.Valid && time.Now().UTC().After(expires.Time) {
		_, _ = s.db.Exec(`DELETE FROM sessions WHERE id = $1`, hash)
		return nil, fmt.Errorf("session expired")
	}
	return sanitizeUser(user), nil
}

func (s *PGStore) DeleteSession(sessionID string) error {
	hash := hashString(sessionID)
	_, err := s.db.Exec(`DELETE FROM sessions WHERE id = $1`, hash)
	if err != nil {
		return fmt.Errorf("deleting session: %w", err)
	}
	return nil
}

func (s *PGStore) DeleteAllSessionsForUser(userID string) error {
	_, err := s.db.Exec(`DELETE FROM sessions WHERE user_id = $1`, userID)
	if err != nil {
		return fmt.Errorf("deleting sessions for user: %w", err)
	}
	return nil
}

func (s *PGStore) Close() error {
	return s.db.Close()
}
