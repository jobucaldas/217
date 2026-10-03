package store

import (
	"database/sql"
	"fmt"
	"strings"

	"217/backend/internal/model"
)

func (s *PGStore) GetUserByID(userID string) (*model.User, error) {
	user := &model.User{}
	err := s.db.QueryRow(
		`SELECT id, email, name, COALESCE(role, ''), api_key, password_hash, created_at, updated_at
		 FROM users WHERE id = $1`, userID,
	).Scan(&user.ID, &user.Email, &user.Name, &user.Role, &user.APIKey, &user.PasswordHash, &user.CreatedAt, &user.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("user not found")
	}
	if err != nil {
		return nil, fmt.Errorf("getting user: %w", err)
	}
	return sanitizeUser(user), nil
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
	res, err := s.db.Exec(`DELETE FROM users WHERE id = $1`, userID)
	if err != nil {
		return fmt.Errorf("deleting user: %w", err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("user not found")
	}
	return nil
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
		err := s.db.QueryRow(
			`SELECT id, owner_id, partner_id, invite_code, status, created_at, updated_at
			 FROM calendar_shares
			 WHERE owner_id = $1 AND status IN ('open', 'active')
			 LIMIT 1`, user.ID,
		).Scan(&share.ID, &share.OwnerID, &partnerID, &share.InviteCode, &share.Status, &share.CreatedAt, &share.UpdatedAt)
		if err == sql.ErrNoRows {
			_ = s.db.QueryRow(
				`SELECT COUNT(*) FROM partner_notes WHERE owner_id = $1 AND read_at IS NULL`, user.ID,
			).Scan(&state.UnreadNotes)
			return state, nil
		}
		if err != nil {
			return nil, fmt.Errorf("loading owner share: %w", err)
		}
		state.Status = share.Status
		state.InviteCode = share.InviteCode
		state.CanEditCalendar = true
		if partnerID.Valid {
			share.PartnerID = partnerID.String
			var email, name string
			if err := s.db.QueryRow(`SELECT email, name FROM users WHERE id = $1`, partnerID.String).
				Scan(&email, &name); err == nil {
				state.PartnerEmail = email
				state.PartnerName = name
			}
		}
		_ = s.db.QueryRow(
			`SELECT COUNT(*) FROM partner_notes WHERE owner_id = $1 AND read_at IS NULL`, user.ID,
		).Scan(&state.UnreadNotes)
		return state, nil
	}

	var share model.CalendarShare
	err := s.db.QueryRow(
		`SELECT id, owner_id, COALESCE(partner_id::text, ''), invite_code, status, created_at, updated_at
		 FROM calendar_shares
		 WHERE partner_id = $1 AND status IN ('open', 'active')
		 LIMIT 1`, user.ID,
	).Scan(&share.ID, &share.OwnerID, &share.PartnerID, &share.InviteCode, &share.Status, &share.CreatedAt, &share.UpdatedAt)
	if err == sql.ErrNoRows {
		err = s.db.QueryRow(
			`SELECT id, owner_id, COALESCE(partner_id::text, ''), invite_code, status, created_at, updated_at
			 FROM calendar_shares
			 WHERE partner_id = $1
			 ORDER BY updated_at DESC LIMIT 1`, user.ID,
		).Scan(&share.ID, &share.OwnerID, &share.PartnerID, &share.InviteCode, &share.Status, &share.CreatedAt, &share.UpdatedAt)
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
	var ownerName, ownerEmail string
	if err := s.db.QueryRow(`SELECT name, email FROM users WHERE id = $1`, share.OwnerID).
		Scan(&ownerName, &ownerEmail); err == nil {
		state.OwnerName = ownerName
		state.OwnerEmail = ownerEmail
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
	code, err := generateInviteCode()
	if err != nil {
		return nil, err
	}
	_, err = s.db.Exec(
		`INSERT INTO calendar_shares (owner_id, invite_code, status)
		 VALUES ($1, $2, 'open')`, ownerID, code,
	)
	if err != nil {
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

	partner := &model.User{}
	err = tx.QueryRow(
		`SELECT id, email, name, COALESCE(role, ''), api_key, password_hash, created_at, updated_at
		 FROM users WHERE id = $1 FOR UPDATE`, partnerID,
	).Scan(&partner.ID, &partner.Email, &partner.Name, &partner.Role, &partner.APIKey, &partner.PasswordHash, &partner.CreatedAt, &partner.UpdatedAt)
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

	var shareID, ownerID string
	err = tx.QueryRow(
		`SELECT id, owner_id FROM calendar_shares
		 WHERE invite_code = $1 AND status = 'open' FOR UPDATE`, code,
	).Scan(&shareID, &ownerID)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("invalid or expired invite code")
	}
	if err != nil {
		return nil, err
	}
	if ownerID == partnerID {
		return nil, fmt.Errorf("cannot accept your own invite")
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
	return s.buildShareState(sanitizeUser(partner))
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

func (s *PGStore) ListInboxNotes(ownerID string) ([]*model.PartnerNote, error) {
	user, err := s.GetUserByID(ownerID)
	if err != nil {
		return nil, err
	}
	if model.NormalizeRole(user.Role) != model.RoleOwner {
		return nil, fmt.Errorf("only owners have an inbox")
	}
	rows, err := s.db.Query(
		`SELECT n.id, n.owner_id, n.partner_id, n.body, n.created_at, n.read_at,
		        COALESCE(u.name, ''), COALESCE(u.email, '')
		 FROM partner_notes n
		 LEFT JOIN users u ON u.id = n.partner_id
		 WHERE n.owner_id = $1
		 ORDER BY n.created_at DESC`, ownerID,
	)
	if err != nil {
		return nil, fmt.Errorf("listing inbox: %w", err)
	}
	defer rows.Close()
	out := make([]*model.PartnerNote, 0)
	for rows.Next() {
		note := &model.PartnerNote{}
		var readAt sql.NullTime
		if err := rows.Scan(
			&note.ID, &note.OwnerID, &note.PartnerID, &note.Body, &note.CreatedAt, &readAt,
			&note.FromName, &note.FromEmail,
		); err != nil {
			return nil, err
		}
		if readAt.Valid {
			t := readAt.Time
			note.ReadAt = &t
		}
		out = append(out, note)
	}
	return out, rows.Err()
}

func (s *PGStore) CreatePartnerNote(partnerID, body string) (*model.PartnerNote, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return nil, fmt.Errorf("note body required")
	}
	if len(body) > 2000 {
		return nil, fmt.Errorf("note too long")
	}
	user, err := s.GetUserByID(partnerID)
	if err != nil {
		return nil, err
	}
	if model.NormalizeRole(user.Role) != model.RolePartner {
		return nil, fmt.Errorf("only partners can leave inbox notes")
	}
	var ownerID string
	err = s.db.QueryRow(
		`SELECT owner_id FROM calendar_shares
		 WHERE partner_id = $1 AND status = 'active' LIMIT 1`, partnerID,
	).Scan(&ownerID)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("share inactive")
	}
	if err != nil {
		return nil, err
	}
	note := &model.PartnerNote{}
	err = s.db.QueryRow(
		`INSERT INTO partner_notes (owner_id, partner_id, body)
		 VALUES ($1, $2, $3)
		 RETURNING id, owner_id, partner_id, body, created_at`,
		ownerID, partnerID, body,
	).Scan(&note.ID, &note.OwnerID, &note.PartnerID, &note.Body, &note.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("creating partner note: %w", err)
	}
	note.FromName = user.Name
	note.FromEmail = user.Email
	return note, nil
}

func (s *PGStore) MarkInboxNoteRead(ownerID, noteID string) error {
	res, err := s.db.Exec(
		`UPDATE partner_notes SET read_at = COALESCE(read_at, NOW())
		 WHERE id = $1 AND owner_id = $2`, noteID, ownerID,
	)
	if err != nil {
		return fmt.Errorf("marking note read: %w", err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("note not found")
	}
	return nil
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
