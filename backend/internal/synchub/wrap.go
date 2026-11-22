package synchub

import (
	"217/backend/internal/model"
	"217/backend/internal/store"
)

// Wrap returns s with hub updates applied after each successful write, and
// makes the hub load sessions from s. Every Store method is classified in
// hub_test.go so a new one cannot skip the hub unnoticed.
func Wrap(s store.Store, h *Hub) store.Store {
	h.src = s
	return &wrapped{Store: s, hub: h}
}

type wrapped struct {
	store.Store
	hub *Hub
}

// bumpPeer also marks the other side of the user's active share.
func (w *wrapped) bumpPeer(userID, prefix string) {
	if peer, err := w.Store.ActivePeer(userID); err == nil && peer != "" {
		w.hub.Bump(prefix + peer)
	}
}

func (w *wrapped) UpsertEntry(userID, date string, req model.UpsertRequest) (*model.Entry, error) {
	e, err := w.Store.UpsertEntry(userID, date, req)
	if err == nil {
		w.hub.Bump("c:" + userID)
	}
	return e, err
}

func (w *wrapped) DeleteEntry(userID, date string) error {
	err := w.Store.DeleteEntry(userID, date)
	if err == nil {
		w.hub.Bump("c:" + userID)
	}
	return err
}

func (w *wrapped) SetStage(userID, stage string) (*model.User, error) {
	u, err := w.Store.SetStage(userID, stage)
	if err == nil {
		w.hub.Bump("c:" + userID)
	}
	return u, err
}

func (w *wrapped) SetProfile(userID string, displayName, birthDate *string) (*model.User, error) {
	u, err := w.Store.SetProfile(userID, displayName, birthDate)
	if err == nil {
		w.hub.Bump("a:" + userID)
		if displayName != nil {
			// The name is shown on the other side (owner_name/partner_name).
			w.hub.Bump("c:" + userID)
			w.bumpPeer(userID, "a:")
		}
	}
	return u, err
}

func (w *wrapped) SendMessage(senderID, body string) (*model.Message, error) {
	m, err := w.Store.SendMessage(senderID, body)
	if err == nil {
		w.hub.Bump("i:"+m.OwnerID, "i:"+m.PartnerID)
	}
	return m, err
}

func (w *wrapped) MarkMessageRead(userID, messageID string) error {
	err := w.Store.MarkMessageRead(userID, messageID)
	if err == nil {
		w.hub.Bump("i:" + userID)
		// The sender sees read_at on the sent message.
		w.bumpPeer(userID, "i:")
	}
	return err
}

func (w *wrapped) UpsertPartnerAlerts(userID string, pref model.PartnerAlertPreference) (*model.PartnerAlertPreference, error) {
	p, err := w.Store.UpsertPartnerAlerts(userID, pref)
	if err == nil {
		w.hub.Bump("p:" + userID)
	}
	return p, err
}

func (w *wrapped) UpsertReminderPreference(userID string, preference model.ReminderPreference) (*model.ReminderPreference, error) {
	p, err := w.Store.UpsertReminderPreference(userID, preference)
	if err == nil {
		w.hub.Bump("p:" + userID)
	}
	return p, err
}

// peerOf returns the other side of the user's active share. ok is false when
// it cannot be determined, which callers answer with a full flush.
func (w *wrapped) peerOf(userID string) (peer string, ok bool) {
	peer, err := w.Store.ActivePeer(userID)
	return peer, err == nil
}

// drop invalidates the cached sessions of the users a write affected, or all
// of them when that set is unknown.
func (w *wrapped) drop(known bool, userIDs ...string) {
	if !known {
		w.hub.Flush()
		return
	}
	w.hub.Invalidate(userIDs...)
}

// The writes below change who may see what: drop the cached sessions of the
// acting user and the other side of their share. Dropping even when the store
// returns an error is cheap and fail-safe when a write commits before a
// follow-up read fails (e.g. RevokeShare). When the peer cannot be looked up,
// or only a token is known, they flush every session instead.

func (w *wrapped) RecordConsent(userID string, version int) (*model.User, error) {
	peer, ok := w.peerOf(userID)
	defer func() { w.drop(ok, userID, peer) }()
	return w.Store.RecordConsent(userID, version)
}

func (w *wrapped) SetRole(userID, role string) (*model.User, error) {
	peer, ok := w.peerOf(userID)
	defer func() { w.drop(ok, userID, peer) }()
	return w.Store.SetRole(userID, role)
}

func (w *wrapped) EnableShare(ownerID string) (*model.ShareState, error) {
	peer, ok := w.peerOf(ownerID)
	defer func() { w.drop(ok, ownerID, peer) }()
	st, err := w.Store.EnableShare(ownerID)
	w.hub.Bump("a:" + ownerID)
	return st, err
}

func (w *wrapped) RevokeShare(ownerID string) (*model.ShareState, error) {
	peer, ok := w.peerOf(ownerID)
	defer func() { w.drop(ok, ownerID, peer) }()
	st, err := w.Store.RevokeShare(ownerID)
	w.hub.Bump("a:"+ownerID, "c:"+ownerID, "i:"+ownerID)
	if peer != "" {
		w.hub.Bump("a:"+peer, "i:"+peer)
	}
	return st, err
}

func (w *wrapped) AcceptShare(partnerID, inviteCode string) (*model.ShareState, error) {
	before, beforeOK := w.peerOf(partnerID)
	st, err := w.Store.AcceptShare(partnerID, inviteCode)
	// The owner is only known afterwards.
	after, afterOK := w.peerOf(partnerID)
	w.drop(beforeOK && afterOK, partnerID, before, after)
	if err == nil {
		w.hub.Bump("a:" + partnerID)
		w.bumpPeer(partnerID, "a:")
	}
	return st, err
}

// DeleteUser marks the other side of the share like RevokeShare does: the
// owner's data and messages are gone for the partner.
func (w *wrapped) DeleteUser(userID string) error {
	peer, ok := w.peerOf(userID)
	defer func() { w.drop(ok, userID, peer) }()
	err := w.Store.DeleteUser(userID)
	if err == nil {
		if peer != "" {
			w.hub.Bump("a:"+peer, "i:"+peer)
		}
		w.hub.forget(userID)
	}
	return err
}

func (w *wrapped) DeleteSession(sessionID string) error {
	defer w.hub.invalidateToken(sessionID)
	return w.Store.DeleteSession(sessionID)
}

// A device key can back other sessions, all of the same user: drop that
// user's, or every session when the user cannot be told.
func (w *wrapped) DeleteSessionAndDevice(sessionID string) error {
	user, _, err := w.Store.GetSessionPrincipal(sessionID)
	known := err == nil && user != nil
	defer func() {
		if known {
			w.drop(true, user.ID)
		} else {
			w.drop(false)
		}
	}()
	return w.Store.DeleteSessionAndDevice(sessionID)
}

func (w *wrapped) DeleteAllSessionsForUser(userID string) error {
	defer w.hub.Invalidate(userID)
	return w.Store.DeleteAllSessionsForUser(userID)
}

func (w *wrapped) CreateDeviceKey(userID string, publicKey []byte) (string, error) {
	defer w.hub.Invalidate(userID)
	return w.Store.CreateDeviceKey(userID, publicKey)
}

func (w *wrapped) LinkWorkOSIdentity(subject, verifiedEmail, name string, authoritative bool) (*model.User, error) {
	u, err := w.Store.LinkWorkOSIdentity(subject, verifiedEmail, name, authoritative)
	if err != nil || u == nil {
		w.hub.Flush() // the user is unknown
	} else {
		w.hub.Invalidate(u.ID)
	}
	return u, err
}
