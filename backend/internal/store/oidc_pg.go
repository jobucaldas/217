package store

import (
	"context"
	"database/sql"
	"fmt"

	"217/backend/internal/model"
)

func (s *PGStore) LinkOIDCIdentity(issuer, subject, email, name string, verified bool) (*model.User, error) {
	email = normalizeEmail(email)
	index := emailIndex(s.kr, email)
	tx, err := s.db.BeginTx(context.Background(), &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`SELECT pg_advisory_xact_lock(hashtextextended($1, 219))`, fmt.Sprintf("%d:%s%s", len(issuer), issuer, subject)); err != nil {
		return nil, err
	}
	if _, err := tx.Exec(`SELECT pg_advisory_xact_lock(hashtextextended(encode($1::bytea, 'hex'), 218))`, index); err != nil {
		return nil, err
	}
	u, err := s.scanUser(tx.QueryRow(`SELECT `+userColumns+` FROM oidc_identities i JOIN users u ON u.id=i.user_id WHERE i.issuer=$1 AND i.subject=$2`, issuer, subject))
	if err == nil {
		if err := tx.Commit(); err != nil {
			return nil, err
		}
		return u, nil
	}
	if err != sql.ErrNoRows {
		return nil, err
	}
	var count int
	if err := tx.QueryRow(`SELECT count(*) FROM users WHERE email_index=$1`, index).Scan(&count); err != nil {
		return nil, err
	}
	if count > 1 {
		return nil, fmt.Errorf("ambiguous email")
	}
	if count == 1 && !verified {
		return nil, fmt.Errorf("account exists: sign in and connect from settings")
	}
	if count == 1 {
		u, err = s.scanUser(tx.QueryRow(`SELECT `+userColumns+` FROM users u WHERE u.email_index=$1 FOR UPDATE`, index))
	} else {
		if name == "" {
			name = email
		}
		u, err = s.insertUser(tx, email, name, "")
	}
	if err != nil {
		return nil, err
	}
	if _, err = tx.Exec(`INSERT INTO oidc_identities(issuer,subject,user_id) VALUES ($1,$2,$3)`, issuer, subject, u.ID); err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return u, nil
}

func (s *PGStore) AttachOIDCIdentity(userID, issuer, subject string) error {
	_, err := s.db.Exec(`INSERT INTO oidc_identities(issuer,subject,user_id) VALUES ($1,$2,$3)`, issuer, subject, userID)
	return err
}

func (s *PGStore) DeleteOIDCIdentity(userID, issuer string) error {
	_, err := s.db.Exec(`DELETE FROM oidc_identities WHERE user_id=$1 AND issuer=$2`, userID, issuer)
	return err
}

func (s *PGStore) OIDCIdentities(userID string) ([]model.OIDCIdentity, error) {
	rows, err := s.db.Query(`SELECT issuer,subject FROM oidc_identities WHERE user_id=$1 ORDER BY issuer`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var identities []model.OIDCIdentity
	for rows.Next() {
		var identity model.OIDCIdentity
		if err := rows.Scan(&identity.Issuer, &identity.Subject); err != nil {
			return nil, err
		}
		identities = append(identities, identity)
	}
	return identities, rows.Err()
}
