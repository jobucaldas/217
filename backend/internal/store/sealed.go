package store

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"

	"217/backend/db"
	"217/backend/internal/fieldcrypt"
	"217/backend/internal/model"
	"github.com/google/uuid"
)

// Personal data is sealed with these contexts, which name the table, the row
// and its owners, so a sealed value only opens on the row it was written for.
func canonID(id string) string {
	if u, err := uuid.Parse(id); err == nil {
		return u.String()
	}
	return id
}

func userEmailCtx(userID string) string { return "users.email|" + canonID(userID) }
func userNameCtx(userID string) string  { return "users.name|" + canonID(userID) }

// Entries are unique per (user, date), which therefore identifies the row.
func entryCtx(userID, date string) string {
	return "entries|" + canonID(userID) + "|" + date
}
func noteCtx(noteID, ownerID, partnerID string) string {
	return "partner_notes|" + canonID(noteID) + "|" + canonID(ownerID) + "|" + canonID(partnerID)
}
func inviteCtx(shareID, ownerID string) string {
	return "calendar_shares.invite|" + canonID(shareID) + "|" + canonID(ownerID)
}
func pushCtx(subscriptionID, userID string) string {
	return "push_subscriptions|" + canonID(subscriptionID) + "|" + canonID(userID)
}
func oauthCtx(stateHash string) string { return "oauth_attempts|" + stateHash }

func emailIndex(kr *fieldcrypt.Keyring, email string) []byte {
	return kr.Index("email", normalizeEmail(email))
}
func inviteIndex(kr *fieldcrypt.Keyring, code string) []byte {
	return kr.Index("invite", normalizeInviteCode(code))
}
func endpointIndex(kr *fieldcrypt.Keyring, endpoint string) []byte {
	return kr.Index("push-endpoint", endpoint)
}

// entryPayload is the sealed part of an entry: everything but who and when.
type entryPayload struct {
	Taken  *bool  `json:"taken"`
	Notes  string `json:"notes"`
	Heart  bool   `json:"heart"`
	Period bool   `json:"period"`
}

type pushPayload struct {
	Endpoint string `json:"endpoint"`
	P256DH   string `json:"p256dh"`
	Auth     string `json:"auth"`
}

type oauthPayload struct {
	CodeVerifier string `json:"code_verifier"`
	Nonce        string `json:"nonce"`
}

func sealJSON(kr *fieldcrypt.Keyring, v any, ctx string) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		panic(fmt.Sprintf("sealing %s: %v", ctx, err)) // plain structs always marshal
	}
	return kr.Seal(b, ctx)
}

func openJSON(kr *fieldcrypt.Keyring, sealed []byte, ctx string, v any) error {
	b, err := kr.Open(sealed, ctx)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

func (s *PGStore) sealEntry(userID, date string, req model.UpsertRequest) []byte {
	return sealJSON(s.kr, entryPayload{Taken: req.Taken, Notes: req.Notes, Heart: req.Heart, Period: req.Period}, entryCtx(userID, date))
}

func (s *PGStore) openEntry(e *model.Entry, sealed []byte) error {
	var p entryPayload
	if err := openJSON(s.kr, sealed, entryCtx(e.UserID, e.Date), &p); err != nil {
		return fmt.Errorf("opening entry %s: %w", e.ID, err)
	}
	e.Taken, e.Notes, e.Heart, e.Period = p.Taken, p.Notes, p.Heart, p.Period
	return nil
}

func (s *PGStore) openUser(user *model.User, email, name []byte) error {
	var err error
	if user.Email, err = s.kr.OpenString(email, userEmailCtx(user.ID)); err != nil {
		return fmt.Errorf("opening user %s email: %w", user.ID, err)
	}
	if user.Name, err = s.kr.OpenString(name, userNameCtx(user.ID)); err != nil {
		return fmt.Errorf("opening user %s name: %w", user.ID, err)
	}
	return nil
}

// sealedColumns lists every sealed column, for key checks.
var sealedColumns = []struct{ table, column string }{
	{"users", "email_sealed"}, {"users", "name_sealed"}, {"entries", "sealed"},
	{"partner_notes", "body_sealed"}, {"calendar_shares", "invite_sealed"},
	{"push_subscriptions", "sealed"}, {"oauth_attempts", "sealed"},
}

// MigrationSteps returns the Go-coded migrations, bound to kr.
func MigrationSteps(kr *fieldcrypt.Keyring) map[string]db.Step {
	return map[string]db.Step{
		"018_seal_existing_rows":    {Tx: func(tx *sql.Tx) error { return sealExistingRows(tx, kr) }},
		"019_rewrite_sealed_tables": {NoTx: rewriteSealedTables},
	}
}

// dropPlaintext removes the plaintext columns (and their indexes) once every
// row is sealed. It runs in the same transaction as the sealing, so plaintext
// is never dropped unless its sealed copy committed with it.
const dropPlaintext = `
ALTER TABLE users
    DROP COLUMN IF EXISTS email,
    DROP COLUMN IF EXISTS name,
    ALTER COLUMN email_sealed SET NOT NULL,
    ALTER COLUMN name_sealed SET NOT NULL,
    ALTER COLUMN email_index SET NOT NULL;
DROP INDEX IF EXISTS idx_users_email;
DROP INDEX IF EXISTS idx_users_email_normalized;
CREATE INDEX IF NOT EXISTS idx_users_email_index ON users (email_index);

DROP INDEX IF EXISTS idx_entries_user_period;
ALTER TABLE entries
    DROP COLUMN IF EXISTS taken,
    DROP COLUMN IF EXISTS notes,
    DROP COLUMN IF EXISTS heart,
    DROP COLUMN IF EXISTS period,
    ALTER COLUMN sealed SET NOT NULL;

ALTER TABLE partner_notes
    DROP COLUMN IF EXISTS body,
    ALTER COLUMN body_sealed SET NOT NULL;

DROP INDEX IF EXISTS idx_calendar_shares_invite_code;
ALTER TABLE calendar_shares
    DROP COLUMN IF EXISTS invite_code,
    ALTER COLUMN invite_sealed SET NOT NULL,
    ALTER COLUMN invite_index SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_calendar_shares_invite_index ON calendar_shares (invite_index);

ALTER TABLE push_subscriptions
    DROP COLUMN IF EXISTS endpoint,
    DROP COLUMN IF EXISTS p256dh,
    DROP COLUMN IF EXISTS auth,
    ALTER COLUMN sealed SET NOT NULL,
    ALTER COLUMN endpoint_index SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_push_subscriptions_endpoint_index ON push_subscriptions (endpoint_index);
`

// sealExistingRows seals rows written before 017, then drops the plaintext.
func sealExistingRows(tx *sql.Tx, kr *fieldcrypt.Keyring) error {
	type row struct {
		id, a, b, c string
		taken       sql.NullBool
		heart, per  bool
		notes, d    string
	}
	collect := func(query string, scan func(*sql.Rows, *row) error) ([]row, error) {
		rows, err := tx.Query(query)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		var out []row
		for rows.Next() {
			var r row
			if err := scan(rows, &r); err != nil {
				return nil, err
			}
			out = append(out, r)
		}
		return out, rows.Err()
	}

	users, err := collect(`SELECT id, email, name FROM users WHERE email_sealed IS NULL`,
		func(rs *sql.Rows, r *row) error { return rs.Scan(&r.id, &r.a, &r.b) })
	if err != nil {
		return fmt.Errorf("reading users: %w", err)
	}
	for _, r := range users {
		if _, err := tx.Exec(`UPDATE users SET email_sealed = $2, name_sealed = $3, email_index = $4 WHERE id = $1`,
			r.id, kr.SealString(r.a, userEmailCtx(r.id)), kr.SealString(r.b, userNameCtx(r.id)), emailIndex(kr, r.a)); err != nil {
			return fmt.Errorf("sealing user: %w", err)
		}
	}

	entries, err := collect(`SELECT id, user_id, to_char(date, 'YYYY-MM-DD'), taken, notes, heart, period FROM entries WHERE sealed IS NULL`,
		func(rs *sql.Rows, r *row) error {
			return rs.Scan(&r.id, &r.a, &r.b, &r.taken, &r.notes, &r.heart, &r.per)
		})
	if err != nil {
		return fmt.Errorf("reading entries: %w", err)
	}
	for _, r := range entries {
		p := entryPayload{Notes: r.notes, Heart: r.heart, Period: r.per}
		if r.taken.Valid {
			p.Taken = model.BoolPtr(r.taken.Bool)
		}
		if _, err := tx.Exec(`UPDATE entries SET sealed = $2 WHERE id = $1`, r.id, sealJSON(kr, p, entryCtx(r.a, r.b))); err != nil {
			return fmt.Errorf("sealing entry: %w", err)
		}
	}

	notes, err := collect(`SELECT id, owner_id, partner_id, body FROM partner_notes WHERE body_sealed IS NULL`,
		func(rs *sql.Rows, r *row) error { return rs.Scan(&r.id, &r.a, &r.b, &r.c) })
	if err != nil {
		return fmt.Errorf("reading partner notes: %w", err)
	}
	for _, r := range notes {
		if _, err := tx.Exec(`UPDATE partner_notes SET body_sealed = $2 WHERE id = $1`, r.id, kr.SealString(r.c, noteCtx(r.id, r.a, r.b))); err != nil {
			return fmt.Errorf("sealing partner note: %w", err)
		}
	}

	shares, err := collect(`SELECT id, owner_id, invite_code FROM calendar_shares WHERE invite_sealed IS NULL`,
		func(rs *sql.Rows, r *row) error { return rs.Scan(&r.id, &r.a, &r.b) })
	if err != nil {
		return fmt.Errorf("reading shares: %w", err)
	}
	for _, r := range shares {
		if _, err := tx.Exec(`UPDATE calendar_shares SET invite_sealed = $2, invite_index = $3 WHERE id = $1`,
			r.id, kr.SealString(r.b, inviteCtx(r.id, r.a)), inviteIndex(kr, r.b)); err != nil {
			return fmt.Errorf("sealing share: %w", err)
		}
	}

	subs, err := collect(`SELECT id, user_id, endpoint, p256dh, auth FROM push_subscriptions WHERE sealed IS NULL`,
		func(rs *sql.Rows, r *row) error { return rs.Scan(&r.id, &r.a, &r.b, &r.c, &r.d) })
	if err != nil {
		return fmt.Errorf("reading push subscriptions: %w", err)
	}
	for _, r := range subs {
		sealed := sealJSON(kr, pushPayload{Endpoint: r.b, P256DH: r.c, Auth: r.d}, pushCtx(r.id, r.a))
		if _, err := tx.Exec(`UPDATE push_subscriptions SET sealed = $2, endpoint_index = $3 WHERE id = $1`,
			r.id, sealed, endpointIndex(kr, r.b)); err != nil {
			return fmt.Errorf("sealing push subscription: %w", err)
		}
	}

	if _, err := tx.Exec(dropPlaintext); err != nil {
		return fmt.Errorf("dropping plaintext columns: %w", err)
	}
	return nil
}

// rewriteSealedTables rewrites the tables that held plaintext. DROP COLUMN
// only hides a column: its bytes stay in the table files (and in dead row
// versions left by sealing) until a rewrite, which VACUUM FULL performs,
// nulling dropped columns. A checkpoint then lets old WAL segments be
// recycled. Safe to repeat if interrupted.
func rewriteSealedTables(conn *sql.DB) error {
	for _, table := range []string{"users", "entries", "partner_notes", "calendar_shares", "push_subscriptions", "sessions", "workos_identities", "oauth_attempts"} {
		if _, err := conn.Exec(`VACUUM FULL ` + table); err != nil {
			return fmt.Errorf("rewriting %s: %w", table, err)
		}
	}
	if _, err := conn.Exec(`CHECKPOINT`); err != nil {
		// Needs superuser or pg_checkpoint; the server checkpoints on its own anyway.
		log.Printf("checkpoint after rewrite skipped: %v", err)
	}
	return nil
}

// checkKey fails fast when the keyring cannot open the stored data (wrong
// DATA_ENCRYPTION_KEY, or a rotated key without the previous one): every
// sealed value must carry a known key id, and one is opened for real.
func (s *PGStore) checkKey() error {
	for _, c := range sealedColumns {
		rows, err := s.db.Query(`SELECT DISTINCT substring(` + c.column + ` from 1 for 5) FROM ` + c.table)
		if err != nil {
			return fmt.Errorf("reading sealed %s.%s: %w", c.table, c.column, err)
		}
		for rows.Next() {
			var header []byte
			if err := rows.Scan(&header); err != nil {
				rows.Close()
				return err
			}
			if !s.kr.Known(header) {
				rows.Close()
				return fmt.Errorf("DATA_ENCRYPTION_KEY cannot open %s.%s; after a key change, keep the old key in DATA_ENCRYPTION_KEY_PREVIOUS", c.table, c.column)
			}
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
	}
	var id string
	var email, name []byte
	err := s.db.QueryRow(`SELECT id, email_sealed, name_sealed FROM users LIMIT 1`).Scan(&id, &email, &name)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("reading a sealed value: %w", err)
	}
	if err := s.openUser(&model.User{ID: id}, email, name); err != nil {
		return fmt.Errorf("DATA_ENCRYPTION_KEY does not open the stored data: %w", err)
	}
	return nil
}

// reseal rewrites values sealed with a previous key under the primary key,
// recomputing their blind indexes, so the previous key can then be dropped.
func (s *PGStore) reseal() error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	type sealedRow struct {
		id, a, b string
		x, y     []byte
	}
	collect := func(query string, scan func(*sql.Rows, *sealedRow) error) ([]sealedRow, error) {
		rows, err := tx.Query(query)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		var out []sealedRow
		for rows.Next() {
			var r sealedRow
			if err := scan(rows, &r); err != nil {
				return nil, err
			}
			if !s.kr.Current(r.x) || (r.y != nil && !s.kr.Current(r.y)) {
				out = append(out, r)
			}
		}
		return out, rows.Err()
	}
	count := 0

	users, err := collect(`SELECT id, email_sealed, name_sealed FROM users`,
		func(rs *sql.Rows, r *sealedRow) error { return rs.Scan(&r.id, &r.x, &r.y) })
	if err != nil {
		return fmt.Errorf("reading users: %w", err)
	}
	for _, r := range users {
		u := &model.User{ID: r.id}
		if err := s.openUser(u, r.x, r.y); err != nil {
			return err
		}
		if _, err := tx.Exec(`UPDATE users SET email_sealed = $2, name_sealed = $3, email_index = $4 WHERE id = $1`,
			r.id, s.kr.SealString(u.Email, userEmailCtx(r.id)), s.kr.SealString(u.Name, userNameCtx(r.id)), emailIndex(s.kr, u.Email)); err != nil {
			return fmt.Errorf("resealing user: %w", err)
		}
	}
	count += len(users)

	entries, err := collect(`SELECT id, user_id, to_char(date, 'YYYY-MM-DD'), sealed FROM entries`,
		func(rs *sql.Rows, r *sealedRow) error { return rs.Scan(&r.id, &r.a, &r.b, &r.x) })
	if err != nil {
		return fmt.Errorf("reading entries: %w", err)
	}
	for _, r := range entries {
		plain, err := s.kr.Open(r.x, entryCtx(r.a, r.b))
		if err != nil {
			return fmt.Errorf("opening entry %s: %w", r.id, err)
		}
		if _, err := tx.Exec(`UPDATE entries SET sealed = $2 WHERE id = $1`, r.id, s.kr.Seal(plain, entryCtx(r.a, r.b))); err != nil {
			return fmt.Errorf("resealing entry: %w", err)
		}
	}
	count += len(entries)

	notes, err := collect(`SELECT id, owner_id, partner_id, body_sealed FROM partner_notes`,
		func(rs *sql.Rows, r *sealedRow) error { return rs.Scan(&r.id, &r.a, &r.b, &r.x) })
	if err != nil {
		return fmt.Errorf("reading partner notes: %w", err)
	}
	for _, r := range notes {
		ctx := noteCtx(r.id, r.a, r.b)
		plain, err := s.kr.Open(r.x, ctx)
		if err != nil {
			return fmt.Errorf("opening partner note %s: %w", r.id, err)
		}
		if _, err := tx.Exec(`UPDATE partner_notes SET body_sealed = $2 WHERE id = $1`, r.id, s.kr.Seal(plain, ctx)); err != nil {
			return fmt.Errorf("resealing partner note: %w", err)
		}
	}
	count += len(notes)

	shares, err := collect(`SELECT id, owner_id, invite_sealed FROM calendar_shares`,
		func(rs *sql.Rows, r *sealedRow) error { return rs.Scan(&r.id, &r.a, &r.x) })
	if err != nil {
		return fmt.Errorf("reading shares: %w", err)
	}
	for _, r := range shares {
		ctx := inviteCtx(r.id, r.a)
		code, err := s.kr.OpenString(r.x, ctx)
		if err != nil {
			return fmt.Errorf("opening share %s: %w", r.id, err)
		}
		if _, err := tx.Exec(`UPDATE calendar_shares SET invite_sealed = $2, invite_index = $3 WHERE id = $1`,
			r.id, s.kr.SealString(code, ctx), inviteIndex(s.kr, code)); err != nil {
			return fmt.Errorf("resealing share: %w", err)
		}
	}
	count += len(shares)

	subs, err := collect(`SELECT id, user_id, sealed FROM push_subscriptions`,
		func(rs *sql.Rows, r *sealedRow) error { return rs.Scan(&r.id, &r.a, &r.x) })
	if err != nil {
		return fmt.Errorf("reading push subscriptions: %w", err)
	}
	for _, r := range subs {
		var p pushPayload
		ctx := pushCtx(r.id, r.a)
		if err := openJSON(s.kr, r.x, ctx, &p); err != nil {
			return fmt.Errorf("opening push subscription %s: %w", r.id, err)
		}
		if _, err := tx.Exec(`UPDATE push_subscriptions SET sealed = $2, endpoint_index = $3 WHERE id = $1`,
			r.id, sealJSON(s.kr, p, ctx), endpointIndex(s.kr, p.Endpoint)); err != nil {
			return fmt.Errorf("resealing push subscription: %w", err)
		}
	}
	count += len(subs)

	// In-flight sign-ins (five minutes at most) just restart.
	if _, err := tx.Exec(`DELETE FROM oauth_attempts`); err != nil {
		return fmt.Errorf("clearing oauth attempts: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	if count > 0 {
		log.Printf("resealed %d rows under the primary data encryption key", count)
	}
	return nil
}
