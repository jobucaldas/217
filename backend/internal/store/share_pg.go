package store

import (
	"database/sql"
	"fmt"

	"217/backend/internal/model"
	"github.com/google/uuid"
)

func (s *PGStore) GetUserByID(userID string) (*model.User, error) {
	user, err := s.scanUser(s.db.QueryRow(`SELECT `+userColumns+` FROM users u WHERE u.id = $1`, userID))
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("user not found")
	}
	if err != nil {
		return nil, fmt.Errorf("getting user: %w", err)
	}
	return user, nil
}

func (s *PGStore) WorkOSSubject(userID string) (string, error) {
	var subject string
	err := s.db.QueryRow(
		`SELECT subject FROM workos_identities WHERE user_id = $1 LIMIT 1`, userID,
	).Scan(&subject)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("looking up workos subject: %w", err)
	}
	return subject, nil
}

func (s *PGStore) DeleteUser(userID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("deleting user: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	var lockedID string
	if err := tx.QueryRow(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&lockedID); err != nil {
		if err == sql.ErrNoRows {
			return fmt.Errorf("user not found")
		}
		return fmt.Errorf("locking user for deletion: %w", err)
	}
	// A departing partner leaves the owner's share revoked, not "active"
	// with nobody on the other end (partner_id is set NULL below).
	if _, err := tx.Exec(`UPDATE calendar_shares SET status = 'revoked', updated_at = NOW()
		WHERE partner_id = $1 AND status IN ('open', 'active')`, userID); err != nil {
		return fmt.Errorf("revoking shares: %w", err)
	}
	res, err := tx.Exec(`DELETE FROM users WHERE id = $1`, userID)
	if err != nil {
		return fmt.Errorf("deleting user: %w", err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("user not found")
	}
	return tx.Commit()
}

func (s *PGStore) buildShareState(user *model.User) (*model.ShareState, error) {
	role := model.NormalizeRole(user.Role)
	state := &model.ShareState{
		Status:          model.ShareNone,
		CanEditCalendar: role == model.RoleOwner,
	}
	if role == "" {
		return state, nil
	}
	if role == model.RoleOwner {
		var share model.CalendarShare
		var partnerID sql.NullString
		var invite []byte
		err := s.db.QueryRow(
			`SELECT id, owner_id, partner_id, invite_sealed, status, created_at, updated_at
			 FROM calendar_shares
			 WHERE owner_id = $1 AND status IN ('open', 'active')
			 LIMIT 1`, user.ID,
		).Scan(&share.ID, &share.OwnerID, &partnerID, &invite, &share.Status, &share.CreatedAt, &share.UpdatedAt)
		if err == sql.ErrNoRows {
			state.UnreadNotes = s.unreadMessages(user.ID)
			return state, nil
		}
		if err != nil {
			return nil, fmt.Errorf("loading owner share: %w", err)
		}
		state.Status = share.Status
		if state.InviteCode, err = s.kr.OpenString(invite, inviteCtx(share.ID, share.OwnerID)); err != nil {
			return nil, fmt.Errorf("opening invite code: %w", err)
		}
		state.CanEditCalendar = true
		if partnerID.Valid {
			if partner, err := s.GetUserByID(partnerID.String); err == nil {
				state.PartnerEmail = partner.Email
				state.PartnerName = partner.Name
			}
		}
		state.UnreadNotes = s.unreadMessages(user.ID)
		return state, nil
	}

	var share model.CalendarShare
	err := s.db.QueryRow(
		`SELECT id, owner_id, COALESCE(partner_id::text, ''), status, created_at, updated_at
		 FROM calendar_shares
		 WHERE partner_id = $1 AND status IN ('open', 'active')
		 LIMIT 1`, user.ID,
	).Scan(&share.ID, &share.OwnerID, &share.PartnerID, &share.Status, &share.CreatedAt, &share.UpdatedAt)
	if err == sql.ErrNoRows {
		err = s.db.QueryRow(
			`SELECT id, owner_id, COALESCE(partner_id::text, ''), status, created_at, updated_at
			 FROM calendar_shares
			 WHERE partner_id = $1
			 ORDER BY updated_at DESC LIMIT 1`, user.ID,
		).Scan(&share.ID, &share.OwnerID, &share.PartnerID, &share.Status, &share.CreatedAt, &share.UpdatedAt)
		if err == sql.ErrNoRows {
			// Partner who has not joined a calendar yet.
			return state, nil
		}
		if err != nil {
			return nil, fmt.Errorf("loading partner share history: %w", err)
		}
	} else if err != nil {
		return nil, fmt.Errorf("loading partner share: %w", err)
	}
	state.Status = share.Status
	state.CanEditCalendar = false
	state.UnreadNotes = s.unreadMessages(user.ID)
	if owner, err := s.GetUserByID(share.OwnerID); err == nil {
		state.OwnerName = owner.Name
		state.OwnerEmail = owner.Email
	}
	return state, nil
}

func (s *PGStore) GetShareState(userID string) (*model.ShareState, error) {
	user, err := s.GetUserByID(userID)
	if err != nil {
		return nil, err
	}
	return s.buildShareState(user)
}

func (s *PGStore) EnableShare(ownerID string) (*model.ShareState, error) {
	user, err := s.GetUserByID(ownerID)
	if err != nil {
		return nil, err
	}
	if model.NormalizeRole(user.Role) != model.RoleOwner {
		return nil, fmt.Errorf("only calendar owners can share")
	}
	if state, err := s.buildShareState(user); err == nil &&
		(state.Status == model.ShareOpen || state.Status == model.ShareActive) {
		return state, nil
	}
	// A fresh code rarely collides with a stored one; try again if it does.
	for attempt := 0; ; attempt++ {
		code, err := generateInviteCode()
		if err != nil {
			return nil, err
		}
		id := uuid.NewString() // chosen here: the seal is bound to it
		_, err = s.db.Exec(
			`INSERT INTO calendar_shares (id, owner_id, invite_sealed, invite_index, status)
			 VALUES ($1, $2, $3, $4, 'open')`,
			id, ownerID, s.kr.SealString(code, inviteCtx(id, ownerID)), inviteIndex(s.kr, code),
		)
		if err == nil {
			break
		}
		if attempt < 3 && isUniqueViolation(err, "idx_calendar_shares_invite_index") {
			continue
		}
		return nil, fmt.Errorf("creating share: %w", err)
	}
	return s.buildShareState(user)
}

func (s *PGStore) RevokeShare(ownerID string) (*model.ShareState, error) {
	user, err := s.GetUserByID(ownerID)
	if err != nil {
		return nil, err
	}
	if model.NormalizeRole(user.Role) != model.RoleOwner {
		return nil, fmt.Errorf("only calendar owners can revoke")
	}
	_, err = s.db.Exec(
		`UPDATE calendar_shares
		 SET status = 'revoked', updated_at = NOW()
		 WHERE owner_id = $1 AND status IN ('open', 'active')`, ownerID,
	)
	if err != nil {
		return nil, fmt.Errorf("revoking share: %w", err)
	}
	return s.buildShareState(user)
}

func (s *PGStore) AcceptShare(partnerID, inviteCode string) (*model.ShareState, error) {
	code := normalizeInviteCode(inviteCode)
	if code == "" {
		return nil, fmt.Errorf("invite code required")
	}
	tx, err := s.db.Begin()
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	partner, err := s.scanUser(tx.QueryRow(`SELECT `+userColumns+` FROM users u WHERE u.id = $1 FOR UPDATE`, partnerID))
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("user not found")
	}
	if err != nil {
		return nil, err
	}
	if model.NormalizeRole(partner.Role) == model.RoleOwner {
		return nil, fmt.Errorf("calendar owners cannot join another calendar")
	}
	var partnerLive int
	if err := tx.QueryRow(
		`SELECT COUNT(*) FROM calendar_shares WHERE partner_id = $1 AND status IN ('open', 'active')`, partnerID,
	).Scan(&partnerLive); err != nil {
		return nil, err
	}
	if partnerLive > 0 {
		return nil, fmt.Errorf("already linked to a calendar")
	}

	// Lock the owner before the share, the same order account deletion uses,
	// so a concurrent deletion cannot deadlock with this join.
	var ownerID string
	err = tx.QueryRow(
		`SELECT owner_id FROM calendar_shares
		 WHERE invite_index = $1 AND status = 'open'`, inviteIndex(s.kr, code),
	).Scan(&ownerID)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("invalid or expired invite code")
	}
	if err != nil {
		return nil, err
	}
	if ownerID == partnerID {
		return nil, fmt.Errorf("cannot accept your own invite")
	}
	// Invites outlive notice changes: both sides must have agreed to the
	// current one before the calendar is linked.
	var ownerConsent int
	err = tx.QueryRow(
		`SELECT consent_version FROM users WHERE id = $1 FOR SHARE`, ownerID,
	).Scan(&ownerConsent)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("invalid or expired invite code")
	}
	if err != nil {
		return nil, err
	}
	if ownerConsent < model.ConsentVersion {
		return nil, fmt.Errorf("calendar owner consent required")
	}
	var shareID string
	err = tx.QueryRow(
		`SELECT id FROM calendar_shares
		 WHERE invite_index = $1 AND owner_id = $2 AND status = 'open' FOR UPDATE`,
		inviteIndex(s.kr, code), ownerID,
	).Scan(&shareID)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("invalid or expired invite code")
	}
	if err != nil {
		return nil, err
	}
	if _, err := tx.Exec(`UPDATE users SET role = 'partner', updated_at = NOW() WHERE id = $1`, partnerID); err != nil {
		return nil, err
	}
	if _, err := tx.Exec(
		`UPDATE calendar_shares
		 SET partner_id = $1, status = 'active', updated_at = NOW()
		 WHERE id = $2`, partnerID, shareID,
	); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	partner.Role = model.RolePartner
	return s.buildShareState(partner)
}

func (s *PGStore) CalendarSubjectID(userID string) (string, error) {
	user, err := s.GetUserByID(userID)
	if err != nil {
		return "", err
	}
	switch model.NormalizeRole(user.Role) {
	case model.RoleOwner:
		return userID, nil
	case "":
		return "", fmt.Errorf("role not chosen")
	}
	var ownerID string
	err = s.db.QueryRow(
		`SELECT owner_id FROM calendar_shares
		 WHERE partner_id = $1 AND status = 'active' LIMIT 1`, userID,
	).Scan(&ownerID)
	if err == sql.ErrNoRows {
		return "", fmt.Errorf("share inactive")
	}
	if err != nil {
		return "", err
	}
	return ownerID, nil
}

func (s *PGStore) SetRole(userID, role string) (*model.User, error) {
	role = model.NormalizeRole(role)
	if role == "" {
		return nil, fmt.Errorf("role must be owner or partner")
	}
	tx, err := s.db.Begin()
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()
	var current string
	err = tx.QueryRow(`SELECT COALESCE(role, '') FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&current)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("user not found")
	}
	if err != nil {
		return nil, err
	}
	if current != role {
		var live int
		if err := tx.QueryRow(
			`SELECT COUNT(*) FROM calendar_shares
			 WHERE (owner_id = $1 AND status IN ('open', 'active'))
			    OR (partner_id = $1 AND status = 'active')`, userID,
		).Scan(&live); err != nil {
			return nil, err
		}
		if live > 0 {
			return nil, fmt.Errorf("role locked while a calendar is shared")
		}
		if _, err := tx.Exec(`UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2`, role, userID); err != nil {
			return nil, fmt.Errorf("setting role: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return s.GetUserByID(userID)
}

func (s *PGStore) ListAccountShares(userID string) ([]*model.CalendarShare, error) {
	rows, err := s.db.Query(`SELECT id,owner_id,COALESCE(partner_id::text,''),status,created_at,updated_at FROM calendar_shares WHERE owner_id=$1 OR partner_id=$1 ORDER BY created_at`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []*model.CalendarShare{}
	for rows.Next() {
		v := &model.CalendarShare{}
		if err := rows.Scan(&v.ID, &v.OwnerID, &v.PartnerID, &v.Status, &v.CreatedAt, &v.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}
func (s *PGStore) ListAccountSubscriptions(userID string) ([]model.ExportPushSubscription, error) {
	rows, err := s.db.Query(`SELECT id,sealed FROM push_subscriptions WHERE user_id=$1`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []model.ExportPushSubscription{}
	for rows.Next() {
		var id string
		var sealed []byte
		if err := rows.Scan(&id, &sealed); err != nil {
			return nil, err
		}
		var payload pushPayload
		if err := openJSON(s.kr, sealed, pushCtx(id, userID), &payload); err != nil {
			return nil, err
		}
		out = append(out, model.ExportPushSubscription{Endpoint: payload.Endpoint})
	}
	return out, rows.Err()
}

func (s *PGStore) SetStage(userID, stage string) (*model.User, error) {
	if stage != "cycling" && stage != "perimenopause" && stage != "menopause" {
		return nil, fmt.Errorf("invalid stage")
	}
	user, err := s.GetUserByID(userID)
	if err != nil {
		return nil, err
	}
	if user.EffectiveRole() != model.RoleOwner {
		return nil, fmt.Errorf("only owners may set stage")
	}
	sealed := sealJSON(s.kr, stage, userStageCtx(userID))
	if _, err := s.db.Exec(`UPDATE users SET stage_sealed = $1, updated_at = NOW() WHERE id = $2`, sealed, userID); err != nil {
		return nil, fmt.Errorf("setting stage: %w", err)
	}
	return s.GetUserByID(userID)
}
