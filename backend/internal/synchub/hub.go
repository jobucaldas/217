// Package synchub answers "did anything change for me?" from memory.
//
// It caches authenticated sessions (keyed by a hash of the token, never the
// token itself) and per-user change counters bumped by the Wrap store
// decorator, so a sync status poll with a valid cached session touches no
// database. It is per process: run one API process per database.
package synchub

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"strconv"
	"strings"
	"sync"
	"time"

	"217/backend/internal/model"
	"217/backend/internal/store"
)

const (
	maxCacheAge     = 24 * time.Hour
	defaultCapacity = 10000
	noneTag         = "none"
)

// ErrUnauthorized means the token has no valid session.
var ErrUnauthorized = errors.New("unauthorized")

type Tags struct {
	Account  string `json:"account"`
	Inbox    string `json:"inbox"`
	Calendar string `json:"calendar"`
	Prefs    string `json:"prefs"`
}

// Status is the sync status of one session.
type Status struct {
	ETag           string `json:"etag"`
	UserID         string `json:"user_id"`
	Role           string `json:"role"`
	ShareActive    bool   `json:"share_active"`
	SubjectConsent bool   `json:"subject_consent"`
	Tags           Tags   `json:"tags"`
	// Consent is whether the caller agreed to the current notice.
	Consent bool `json:"-"`
}

type principal struct {
	userID         string
	role           string
	subjectID      string // self for an owner, the owner for an active partner
	consent        bool
	subjectConsent bool
	shareActive    bool
	expires        time.Time
	loaded         time.Time
}

type Hub struct {
	mu  sync.RWMutex
	key [32]byte
	// seq orders invalidations. A Load that started at seq N must not cache
	// when a Flush (flushSeq) or an invalidation of a user or token it
	// touched (inval) happened after N.
	seq      uint64
	flushSeq uint64
	inval    map[string]uint64
	sessions map[[32]byte]*principal
	versions map[string]uint64
	now      func() time.Time
	capacity int
	src      store.Store
}

// New returns a hub with a fresh random key, so tags change on restart.
func New() *Hub {
	h := &Hub{
		sessions: map[[32]byte]*principal{},
		inval:    map[string]uint64{},
		versions: map[string]uint64{},
		now:      time.Now,
		capacity: defaultCapacity,
	}
	if _, err := rand.Read(h.key[:]); err != nil {
		panic(err)
	}
	return h
}

// SetClock replaces time.Now (tests).
func (h *Hub) SetClock(now func() time.Time) { h.now = now }

// Lookup is Cached, then Load on a miss.
func (h *Hub) Lookup(token string) (Status, error) {
	if st, hit, err := h.Cached(token); hit {
		return st, err
	}
	return h.Load(token)
}

// Cached answers from memory only; hit is false when the store is needed.
func (h *Hub) Cached(token string) (st Status, hit bool, err error) {
	id := sha256.Sum256([]byte(token))
	now := h.now()
	h.mu.RLock()
	defer h.mu.RUnlock()
	p := h.sessions[id]
	if p == nil {
		return Status{}, false, nil
	}
	if !now.Before(p.expires) {
		return Status{}, true, ErrUnauthorized
	}
	if now.Sub(p.loaded) >= maxCacheAge {
		return Status{}, false, nil
	}
	return h.statusLocked(p), true, nil
}

// Load reads the session from the store and caches it. If a Flush, or an
// invalidation of a user it depends on, ran during the read, it retries so a
// response never reflects pre-revocation state.
func (h *Hub) Load(token string) (Status, error) {
	if h.src == nil {
		return Status{}, errors.New("synchub: no store")
	}
	const maxLoadAttempts = 3
	id := sha256.Sum256([]byte(token))

	for attempt := 0; attempt < maxLoadAttempts; attempt++ {
		h.mu.RLock()
		startSeq := h.seq
		h.mu.RUnlock()

		user, expires, err := h.src.GetSessionPrincipal(token)
		if errors.Is(err, store.ErrSessionNotFound) {
			return Status{}, ErrUnauthorized
		}
		if err != nil {
			return Status{}, err
		}
		peerID, err := h.src.ActivePeer(user.ID)
		if err != nil {
			return Status{}, err
		}
		p := &principal{
			userID:      user.ID,
			role:        model.NormalizeRole(user.Role),
			consent:     user.HasConsent(),
			shareActive: peerID != "",
			expires:     expires,
			loaded:      h.now(),
		}
		switch {
		case p.role == model.RoleOwner:
			p.subjectID = user.ID
			p.subjectConsent = p.consent
		case p.role == model.RolePartner && peerID != "":
			owner, err := h.src.GetUserByID(peerID)
			if err != nil {
				h.mu.RLock()
				changed := h.staleLocked(startSeq, tokenKey(id), user.ID, peerID)
				h.mu.RUnlock()
				if changed {
					continue
				}
				return Status{}, err
			}
			p.subjectID = peerID
			p.subjectConsent = owner.HasConsent()
		}

		h.mu.Lock()
		if !h.staleLocked(startSeq, tokenKey(id), user.ID, peerID) {
			if len(h.sessions) >= h.capacity {
				clear(h.sessions)
			}
			h.sessions[id] = p
			st := h.statusLocked(p)
			h.mu.Unlock()
			return st, nil
		}
		h.mu.Unlock()
	}
	return Status{}, errors.New("synchub: concurrent authorization change")
}

// Flush drops every cached session; the next poll of each reloads it. Use it
// when the affected users cannot be determined.
func (h *Hub) Flush() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.seq++
	h.flushSeq = h.seq
	clear(h.sessions)
}

// Invalidate drops the cached sessions of the given users, and of anyone whose
// calendar subject is one of them (a partner caches their owner's consent and
// share), so the next poll reloads them. Empty IDs are ignored.
func (h *Hub) Invalidate(userIDs ...string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.seq++
	set := make(map[string]bool, len(userIDs))
	for _, id := range userIDs {
		if id != "" {
			set[id] = true
			h.markLocked(id)
		}
	}
	for id, p := range h.sessions {
		if set[p.userID] || set[p.subjectID] {
			delete(h.sessions, id)
		}
	}
}

// invalidateToken drops one cached session (logout).
func (h *Hub) invalidateToken(token string) {
	id := sha256.Sum256([]byte(token))
	h.mu.Lock()
	defer h.mu.Unlock()
	h.seq++
	h.markLocked(tokenKey(id))
	delete(h.sessions, id)
}

func tokenKey(id [32]byte) string { return "t:" + string(id[:]) }

// markLocked records an invalidation for loads in flight. Past capacity it
// degrades to a full flush marker, which is always safe.
func (h *Hub) markLocked(key string) {
	if len(h.inval) >= h.capacity {
		clear(h.inval)
		h.flushSeq = h.seq
	}
	h.inval[key] = h.seq
}

// staleLocked reports whether a load that started at startSeq was overtaken by
// a flush or an invalidation of any of the keys (a token key or user IDs).
func (h *Hub) staleLocked(startSeq uint64, keys ...string) bool {
	if h.flushSeq > startSeq {
		return true
	}
	for _, k := range keys {
		if k != "" && h.inval[k] > startSeq {
			return true
		}
	}
	return false
}

// Bump marks keys ("a:", "i:", "c:", "p:" + user ID) as changed.
func (h *Hub) Bump(keys ...string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, k := range keys {
		h.versions[k]++
	}
}

// forget drops a deleted user's counters.
func (h *Hub) forget(userID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, prefix := range []string{"a:", "i:", "c:", "p:"} {
		delete(h.versions, prefix+userID)
	}
}

func (h *Hub) statusLocked(p *principal) Status {
	v := func(k string) string { return strconv.FormatUint(h.versions[k], 10) }
	tags := Tags{
		Account: h.tag(p.userID, "account", p.role, strconv.FormatBool(p.consent), strconv.FormatBool(p.shareActive),
			p.subjectID, strconv.FormatBool(p.subjectConsent), v("a:"+p.userID)),
		Inbox:    h.tag(p.userID, "inbox", v("i:"+p.userID)),
		Calendar: noneTag,
		Prefs:    h.tag(p.userID, "prefs", v("p:"+p.userID)),
	}
	if p.subjectID != "" && p.subjectConsent {
		tags.Calendar = h.tag(p.userID, "calendar", p.subjectID, v("c:"+p.subjectID))
	}
	return Status{
		ETag:           h.tag(p.userID, "etag", tags.Account, tags.Inbox, tags.Calendar, tags.Prefs),
		UserID:         p.userID,
		Role:           p.role,
		ShareActive:    p.shareActive,
		SubjectConsent: p.subjectConsent,
		Tags:           tags,
		Consent:        p.consent,
	}
}

func (h *Hub) tag(parts ...string) string {
	mac := hmac.New(sha256.New, h.key[:])
	mac.Write([]byte(strings.Join(parts, "\x00")))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))[:16]
}
