package store

import (
	"database/sql"
	"fmt"
	"strings"

	"217/backend/internal/model"
	"github.com/google/uuid"
)

// Messages live in partner_notes: one row per message between an owner and
// a partner, with sender naming which of the two wrote it.

// receivedBy matches the messages written to $1.
const receivedBy = `((owner_id = $1 AND sender = 'partner') OR (partner_id = $1 AND sender = 'owner'))`

func (s *PGStore) unreadMessages(userID string) int {
	var n int
	_ = s.db.QueryRow(`SELECT COUNT(*) FROM partner_notes WHERE `+receivedBy+` AND read_at IS NULL`, userID).Scan(&n)
	return n
}

// queryMessages lists messages matching where (with $1 the caller), newest
// first, opened and labelled from the caller's point of view.
func (s *PGStore) queryMessages(viewerID, where string) ([]*model.Message, error) {
	rows, err := s.db.Query(
		`SELECT id, owner_id, partner_id, sender, body_sealed, created_at, read_at
		 FROM partner_notes WHERE `+where+` ORDER BY created_at DESC`, viewerID,
	)
	if err != nil {
		return nil, fmt.Errorf("listing messages: %w", err)
	}
	out := make([]*model.Message, 0)
	for rows.Next() {
		m := &model.Message{}
		var readAt sql.NullTime
		var body []byte
		if err := rows.Scan(&m.ID, &m.OwnerID, &m.PartnerID, &m.Sender, &body, &m.CreatedAt, &readAt); err != nil {
			rows.Close()
			return nil, err
		}
		if m.Body, err = s.kr.OpenString(body, noteCtx(m.ID, m.OwnerID, m.PartnerID, m.Sender)); err != nil {
			rows.Close()
			return nil, fmt.Errorf("opening message %s: %w", m.ID, err)
		}
		if readAt.Valid {
			t := readAt.Time
			m.ReadAt = &t
		}
		m.FromMe = canonID(m.SenderID()) == canonID(viewerID)
		out = append(out, m)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	senders := map[string]*model.User{}
	for _, m := range out {
		id := m.SenderID()
		if _, ok := senders[id]; !ok {
			senders[id], _ = s.GetUserByID(id)
		}
		if from := senders[id]; from != nil {
			m.FromName, m.FromEmail = from.Name, from.Email
		}
	}
	return out, nil
}

func (s *PGStore) ListMessages(userID string) ([]*model.Message, error) {
	return s.queryMessages(userID, `(owner_id = $1 OR partner_id = $1)`)
}

func (s *PGStore) SendMessage(senderID, body string) (*model.Message, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return nil, fmt.Errorf("message body required")
	}
	if len(body) > 2000 {
		return nil, fmt.Errorf("message too long")
	}
	user, err := s.GetUserByID(senderID)
	if err != nil {
		return nil, err
	}
	// The recipient must have agreed to the current notice: their copy is
	// stored for them as much as for the sender.
	var ownerID, partnerID string
	var recipientConsent int
	consentErr := "calendar owner consent required"
	switch model.NormalizeRole(user.Role) {
	case model.RolePartner:
		partnerID = senderID
		err = s.db.QueryRow(
			`SELECT s.owner_id, u.consent_version FROM calendar_shares s
			 JOIN users u ON u.id = s.owner_id
			 WHERE s.partner_id = $1 AND s.status = 'active' LIMIT 1`, senderID,
		).Scan(&ownerID, &recipientConsent)
	case model.RoleOwner:
		ownerID = senderID
		consentErr = "partner consent required"
		err = s.db.QueryRow(
			`SELECT s.partner_id, u.consent_version FROM calendar_shares s
			 JOIN users u ON u.id = s.partner_id
			 WHERE s.owner_id = $1 AND s.status = 'active' LIMIT 1`, senderID,
		).Scan(&partnerID, &recipientConsent)
	default:
		err = sql.ErrNoRows
	}
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("share inactive")
	}
	if err != nil {
		return nil, err
	}
	if recipientConsent < model.ConsentVersion {
		return nil, fmt.Errorf("%s", consentErr)
	}
	sender := model.NormalizeRole(user.Role)
	m := &model.Message{Sender: sender, Body: body, FromName: user.Name, FromEmail: user.Email, FromMe: true}
	id := uuid.NewString() // chosen here: the seal is bound to it
	err = s.db.QueryRow(
		`INSERT INTO partner_notes (id, owner_id, partner_id, sender, body_sealed)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, owner_id, partner_id, created_at`,
		id, ownerID, partnerID, sender, s.kr.SealString(body, noteCtx(id, ownerID, partnerID, sender)),
	).Scan(&m.ID, &m.OwnerID, &m.PartnerID, &m.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("creating message: %w", err)
	}
	return m, nil
}

func (s *PGStore) MarkMessageRead(userID, messageID string) error {
	if _, err := uuid.Parse(messageID); err != nil {
		return fmt.Errorf("message not found")
	}
	res, err := s.db.Exec(
		`UPDATE partner_notes SET read_at = COALESCE(read_at, NOW())
		 WHERE `+receivedBy+` AND id = $2`, userID, messageID,
	)
	if err != nil {
		return fmt.Errorf("marking message read: %w", err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("message not found")
	}
	return nil
}
