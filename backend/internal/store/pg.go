package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"217/backend/internal/fieldcrypt"
	"217/backend/internal/model"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"golang.org/x/crypto/bcrypt"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// PGStore keeps personal data sealed with kr (see sealed.go): emails, names,
// entries, partner notes, invite codes, push subscriptions and OAuth secrets
// never reach PostgreSQL in plaintext.
type PGStore struct {
	db *sql.DB
	kr *fieldcrypt.Keyring
}

// NewPGStore connects to an already migrated database. It refuses a key that
// cannot open the stored data and reseals rows left on a previous key.
func NewPGStore(databaseURL string, kr *fieldcrypt.Keyring) (*PGStore, error) {
	if kr == nil {
		return nil, fmt.Errorf("a data encryption key is required")
	}
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("opening database: %w", err)
	}
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("pinging database: %w", err)
	}
	return &PGStore{db: db, kr: kr}, nil
}

// Prepare verifies the key against stored data and, while previous keys are
// configured, reseals values under the primary key. Run it after migrations.
func (s *PGStore) Prepare() error {
	if err := s.checkKey(); err != nil {
		return err
	}
	if s.kr.Rotating() {
		return s.reseal()
	}
	return nil
}

const userColumns = `u.id, u.email_sealed, u.name_sealed, COALESCE(u.role, ''), u.created_at, u.updated_at`

type rowScanner interface{ Scan(dest ...any) error }

// scanUser reads userColumns (plus extra destinations) and opens the sealed fields.
func (s *PGStore) scanUser(row rowScanner, extra ...any) (*model.User, error) {
	user := &model.User{}
	var email, name []byte
	dest := append([]any{&user.ID, &email, &name, &user.Role, &user.CreatedAt, &user.UpdatedAt}, extra...)
	if err := row.Scan(dest...); err != nil {
		return nil, err
	}
	if err := s.openUser(user, email, name); err != nil {
		return nil, err
	}
	return user, nil
}

// insertUser creates a user with sealed email and name. The id is chosen here
// because the seal is bound to it.
func (s *PGStore) insertUser(q interface {
	QueryRow(string, ...any) *sql.Row
}, email, name, passwordHash string) (*model.User, error) {
	id := uuid.NewString()
	return s.scanUser(q.QueryRow(
		`INSERT INTO users AS u (id, email_sealed, name_sealed, email_index, api_key, password_hash)
		 VALUES ($1, $2, $3, $4, $5, $6)
		 RETURNING `+userColumns,
		id, s.kr.SealString(email, userEmailCtx(id)), s.kr.SealString(name, userNameCtx(id)),
		emailIndex(s.kr, email), generateAPIKey(), passwordHash,
	))
}

func (s *PGStore) CreateUser(email, name, password string) (*model.User, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hashing password: %w", err)
	}
	user, err := s.insertUser(s.db, email, name, string(hash))
	if err != nil {
		return nil, fmt.Errorf("creating user: %w", err)
	}
	return user, nil
}

// GetUserByEmail matches the normalized email; several legacy accounts may share it.
func (s *PGStore) GetUserByEmail(email string) (*model.User, error) {
	rows, err := s.db.Query(`SELECT `+userColumns+` FROM users u WHERE u.email_index = $1 LIMIT 2`, emailIndex(s.kr, email))
	if err != nil {
		return nil, fmt.Errorf("getting user: %w", err)
	}
	defer rows.Close()
	var found *model.User
	for rows.Next() {
		if found != nil {
			return nil, fmt.Errorf("ambiguous email")
		}
		if found, err = s.scanUser(rows); err != nil {
			return nil, fmt.Errorf("getting user: %w", err)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("getting user: %w", err)
	}
	if found == nil {
		return nil, fmt.Errorf("user not found")
	}
	return found, nil
}

func formatDate(t time.Time) string {
	return t.Format("2006-01-02")
}

// canonDate rewrites a YYYY-MM-DD date in canonical form; seals are bound to it.
func canonDate(date string) (string, error) {
	d, err := time.Parse("2006-01-02", date)
	if err != nil {
		return "", fmt.Errorf("invalid date %q", date)
	}
	return formatDate(d), nil
}

const entryColumns = `id, user_id, date, sealed, created_at, updated_at`

func (s *PGStore) scanEntry(row rowScanner) (*model.Entry, error) {
	e := &model.Entry{}
	var dateVal time.Time
	var sealed []byte
	if err := row.Scan(&e.ID, &e.UserID, &dateVal, &sealed, &e.CreatedAt, &e.UpdatedAt); err != nil {
		return nil, err
	}
	e.Date = formatDate(dateVal)
	if err := s.openEntry(e, sealed); err != nil {
		return nil, err
	}
	return e, nil
}

func (s *PGStore) GetEntry(userID, date string) (*model.Entry, error) {
	e, err := s.scanEntry(s.db.QueryRow(
		`SELECT `+entryColumns+` FROM entries WHERE user_id = $1 AND date = $2`, userID, date,
	))
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("entry not found")
	}
	if err != nil {
		return nil, fmt.Errorf("getting entry: %w", err)
	}
	return e, nil
}

// listEntriesBetween returns the entries dated within [from, to], oldest first.
func (s *PGStore) listEntriesBetween(userID, from, to string) ([]*model.Entry, error) {
	rows, err := s.db.Query(
		`SELECT `+entryColumns+` FROM entries
		 WHERE user_id = $1 AND date >= $2 AND date <= $3
		 ORDER BY date ASC`,
		userID, from, to,
	)
	if err != nil {
		return nil, fmt.Errorf("listing entries: %w", err)
	}
	defer rows.Close()

	result := []*model.Entry{}
	for rows.Next() {
		e, err := s.scanEntry(rows)
		if err != nil {
			return nil, fmt.Errorf("scanning entry: %w", err)
		}
		result = append(result, e)
	}
	return result, rows.Err()
}

func monthBounds(year, month int) (string, string) {
	first := time.Date(year, time.Month(month), 1, 0, 0, 0, 0, time.UTC)
	return formatDate(first), formatDate(first.AddDate(0, 1, -1))
}

func (s *PGStore) ListEntries(userID string, year, month int) ([]*model.Entry, error) {
	from, to := monthBounds(year, month)
	return s.listEntriesBetween(userID, from, to)
}

func (s *PGStore) UpsertEntry(userID, date string, req model.UpsertRequest) (*model.Entry, error) {
	date, err := canonDate(date)
	if err != nil {
		return nil, err
	}
	e := &model.Entry{}
	var dateVal time.Time
	err = s.db.QueryRow(
		`INSERT INTO entries (user_id, date, sealed)
		 VALUES ($1, $2, $3)
		 ON CONFLICT (user_id, date) DO UPDATE SET
		   sealed = EXCLUDED.sealed,
		   updated_at = NOW()
		 RETURNING id, user_id, date, created_at, updated_at`,
		userID, date, s.sealEntry(userID, date, req),
	).Scan(&e.ID, &e.UserID, &dateVal, &e.CreatedAt, &e.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("upserting entry: %w", err)
	}
	e.Date = formatDate(dateVal)
	e.Taken, e.Notes, e.Heart, e.Period = req.Taken, req.Notes, req.Heart, req.Period
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

// GetStats is computed here rather than in SQL: the taken flags are sealed.
func (s *PGStore) GetStats(userID string, year, month int) (*model.Stats, error) {
	entries, err := s.ListEntries(userID, year, month)
	if err != nil {
		return nil, fmt.Errorf("getting stats: %w", err)
	}
	taken := map[string]bool{}
	takenDays := 0
	for _, e := range entries {
		if model.TakenTrue(e.Taken) {
			taken[e.Date] = true
			takenDays++
		}
	}
	totalDays := time.Date(year, time.Month(month)+1, 0, 0, 0, 0, 0, time.UTC).Day()

	// Consecutive taken days going backwards from today (within this month).
	streak := 0
	for d := time.Now().UTC(); d.Month() == time.Month(month) && d.Year() == year && taken[formatDate(d)]; d = d.AddDate(0, 0, -1) {
		streak++
	}

	return &model.Stats{
		Year:       year,
		Month:      month,
		TotalDays:  totalDays,
		TakenDays:  takenDays,
		MissedDays: totalDays - takenDays,
		Streak:     streak,
	}, nil
}

func (s *PGStore) LinkWorkOSIdentity(subject, verifiedEmail, name string, authoritative bool) (*model.User, error) {
	normalizedEmail := normalizeEmail(verifiedEmail)
	index := emailIndex(s.kr, normalizedEmail)
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
	if _, err := tx.Exec(`SELECT pg_advisory_xact_lock(hashtextextended(encode($1::bytea, 'hex'), 218))`, index); err != nil {
		return nil, fmt.Errorf("locking workos email: %w", err)
	}

	user, err := s.scanUser(tx.QueryRow(`SELECT `+userColumns+`
		FROM workos_identities gi
		JOIN users u ON u.id = gi.user_id
		WHERE gi.subject = $1`, subject))
	if err == nil {
		if err := tx.Commit(); err != nil {
			return nil, fmt.Errorf("committing workos identity lookup: %w", err)
		}
		return user, nil
	}
	if err != sql.ErrNoRows {
		return nil, fmt.Errorf("getting workos identity: %w", err)
	}

	var normalizedMatches int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM users WHERE email_index = $1`, index).Scan(&normalizedMatches); err != nil {
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
		if err := tx.QueryRow(`SELECT EXISTS (SELECT 1 FROM workos_identities gi JOIN users u ON u.id = gi.user_id WHERE u.email_index = $1)`, index).Scan(&alreadyLinked); err != nil {
			return nil, fmt.Errorf("checking existing workos link: %w", err)
		}
		if alreadyLinked {
			return nil, fmt.Errorf("account already linked to another workos subject")
		}
	}

	user, err = s.scanUser(tx.QueryRow(`SELECT `+userColumns+` FROM users u WHERE u.email_index = $1 FOR UPDATE`, index))
	if err == sql.ErrNoRows {
		if name == "" {
			name = normalizedEmail
		}
		user, err = s.insertUser(tx, normalizedEmail, name, "")
	}
	if err != nil {
		return nil, fmt.Errorf("finding user for workos identity: %w", err)
	}

	if _, err = tx.Exec(`INSERT INTO workos_identities (subject, user_id) VALUES ($1, $2)`, subject, user.ID); err != nil {
		return nil, fmt.Errorf("linking workos identity: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("committing workos identity link: %w", err)
	}
	return user, nil
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
	index := endpointIndex(s.kr, request.Endpoint)
	var owner string
	id := uuid.NewString() // the seal is bound to the row id: reuse an existing row's
	err := s.db.QueryRow(`SELECT id, user_id FROM push_subscriptions WHERE endpoint_index = $1`, index).Scan(&id, &owner)
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
	payload := pushPayload{Endpoint: request.Endpoint, P256DH: request.Keys.P256DH, Auth: request.Keys.Auth}
	subscription := &model.PushSubscription{}
	err = s.db.QueryRow(`INSERT INTO push_subscriptions (id, user_id, endpoint_index, sealed)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (endpoint_index) DO UPDATE SET sealed = EXCLUDED.sealed, updated_at = NOW()
		WHERE push_subscriptions.user_id = EXCLUDED.user_id
		RETURNING id, user_id, created_at, updated_at`,
		id, userID, index, sealJSON(s.kr, payload, pushCtx(id, userID))).
		Scan(&subscription.ID, &subscription.UserID, &subscription.CreatedAt, &subscription.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("subscription belongs to another user")
	}
	if err != nil {
		return nil, fmt.Errorf("saving push subscription: %w", err)
	}
	if subscription.ID != canonID(id) {
		// Another request created the row first: bind the seal to its id.
		if _, err := s.db.Exec(`UPDATE push_subscriptions SET sealed = $2 WHERE id = $1`,
			subscription.ID, sealJSON(s.kr, payload, pushCtx(subscription.ID, userID))); err != nil {
			return nil, fmt.Errorf("saving push subscription: %w", err)
		}
	}
	subscription.Endpoint, subscription.P256DH, subscription.Auth = request.Endpoint, request.Keys.P256DH, request.Keys.Auth
	return subscription, nil
}

func (s *PGStore) DeletePushSubscription(userID, endpoint string) error {
	_, err := s.db.Exec(`DELETE FROM push_subscriptions WHERE user_id = $1 AND endpoint_index = $2`, userID, endpointIndex(s.kr, endpoint))
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
	rows, err := s.db.Query(`SELECT ps.id, ps.user_id, ps.sealed, rp.reminder_time, rp.timezone
		FROM push_subscriptions ps
		JOIN users u ON u.id = ps.user_id
		JOIN reminder_preferences rp ON rp.user_id = ps.user_id
		WHERE rp.enabled = TRUE AND COALESCE(u.role, '') <> 'partner'`)
	if err != nil {
		return nil, fmt.Errorf("listing reminder targets: %w", err)
	}
	defer rows.Close()
	result := []model.ReminderTarget{}
	for rows.Next() {
		var target model.ReminderTarget
		var sealed []byte
		if err := rows.Scan(&target.SubscriptionID, &target.UserID, &sealed, &target.Time, &target.Timezone); err != nil {
			return nil, fmt.Errorf("scanning reminder target: %w", err)
		}
		var p pushPayload
		if err := openJSON(s.kr, sealed, pushCtx(target.SubscriptionID, target.UserID), &p); err != nil {
			return nil, fmt.Errorf("opening push subscription %s: %w", target.SubscriptionID, err)
		}
		target.Endpoint, target.P256DH, target.Auth = p.Endpoint, p.P256DH, p.Auth
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
	sealed := sealJSON(s.kr, oauthPayload{CodeVerifier: codeVerifier, Nonce: nonce}, oauthCtx(hash))
	_, err := s.db.Exec(`INSERT INTO oauth_attempts (state_hash, binding_hash, sealed, expires_at, consumed_at)
		VALUES ($1, $2, $3, $4, NULL)`, hash, hashString(binding), sealed, expiresAt)
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

	var sealed []byte
	var expiresAt time.Time
	var consumedAt sql.NullTime
	var bindingHash string
	err = tx.QueryRow(`SELECT sealed, binding_hash, expires_at, consumed_at FROM oauth_attempts WHERE state_hash = $1 FOR UPDATE`, hash).
		Scan(&sealed, &bindingHash, &expiresAt, &consumedAt)
	if err == sql.ErrNoRows {
		return OAuthAttempt{}, fmt.Errorf("oauth state not found")
	}
	if err != nil {
		return OAuthAttempt{}, fmt.Errorf("getting oauth attempt: %w", err)
	}
	if time.Now().UTC().After(expiresAt) {
		_, _ = tx.Exec(`DELETE FROM oauth_attempts WHERE state_hash = $1`, hash)
		_ = tx.Commit()
		return OAuthAttempt{}, fmt.Errorf("oauth state expired")
	}
	if consumedAt.Valid {
		return OAuthAttempt{}, fmt.Errorf("oauth state already used")
	}
	if bindingHash != hashString(binding) {
		return OAuthAttempt{}, fmt.Errorf("oauth browser binding mismatch")
	}
	var p oauthPayload
	if err := openJSON(s.kr, sealed, oauthCtx(hash), &p); err != nil {
		return OAuthAttempt{}, fmt.Errorf("opening oauth attempt: %w", err)
	}
	if _, err := tx.Exec(`UPDATE oauth_attempts SET consumed_at = NOW() WHERE state_hash = $1`, hash); err != nil {
		return OAuthAttempt{}, fmt.Errorf("consuming oauth attempt: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return OAuthAttempt{}, fmt.Errorf("committing oauth attempt: %w", err)
	}
	return OAuthAttempt{CodeVerifier: p.CodeVerifier, Nonce: p.Nonce}, nil
}

func (s *PGStore) CreateSession(userID, sessionID string, expiresAt time.Time) error {
	hash := hashString(sessionID)
	_, _ = s.db.Exec(`DELETE FROM sessions WHERE expires_at <= NOW()`)
	_, err := s.db.Exec(`INSERT INTO sessions (id, user_id, created_at, expires_at)
		VALUES ($1, $2, NOW(), $3)
		ON CONFLICT (id) DO UPDATE SET user_id = EXCLUDED.user_id, expires_at = EXCLUDED.expires_at, created_at = NOW()`,
		hash, userID, expiresAt)
	if err != nil {
		return fmt.Errorf("creating session: %w", err)
	}
	return nil
}

func (s *PGStore) GetUserBySession(sessionID string) (*model.User, error) {
	hash := hashString(sessionID)
	var expires sql.NullTime
	user, err := s.scanUser(s.db.QueryRow(`SELECT `+userColumns+`, s.expires_at
		FROM sessions s JOIN users u ON u.id = s.user_id
		WHERE s.id = $1`, hash), &expires)
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
	return user, nil
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

// isUniqueViolation reports a PostgreSQL unique_violation (23505) on constraint.
func isUniqueViolation(err error, constraint string) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == constraint
}
