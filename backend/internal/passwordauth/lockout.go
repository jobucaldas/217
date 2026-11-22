package passwordauth

import (
	"sync"
	"time"
)

// lockoutPolicy: after 15 wrong attempts an address is locked out for
// 30 minutes, and every further lock adds an hour (30m, 1h, 2h, 3h, ...).
// Counters reset after 24h with no failed attempt.
const (
	lockThreshold  = 15
	lockBase       = 30 * time.Minute
	lockGrowth     = time.Hour
	lockoutWindow  = 24 * time.Hour
	maxLockPenalty = 24 * time.Hour
)

// Lockout tracks failed password attempts per key (per-IP or per-account).
// It is an in-memory limiter on purpose: it guards one server process, and
// a restart only resets to the slow start every attacker begins with.
type Lockout struct {
	mu      sync.Mutex
	attempt map[string]attemptState
}

type attemptState struct {
	failures int
	lockedTo time.Time
	lastTry  time.Time
}

// NewLockout returns a ready-to-use lockout tracker.
func NewLockout() *Lockout {
	return &Lockout{attempt: map[string]attemptState{}}
}

// Locked reports whether key is locked out right now.
func (l *Lockout) Locked(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	a, ok := l.attempt[key]
	if !ok {
		return false
	}
	if time.Now().After(a.lockedTo) {
		return false
	}
	return a.failures >= lockThreshold
}

// RetryAfter returns how long the current lockout still lasts (0 = open).
func (l *Lockout) RetryAfter() time.Duration {
	l.mu.Lock()
	defer l.mu.Unlock()
	var maxTo time.Time
	for _, a := range l.attempt {
		if a.lockedTo.After(maxTo) {
			maxTo = a.lockedTo
		}
	}
	if maxTo.IsZero() {
		return 0
	}
	return time.Until(maxTo)
}

// Fail records a failed attempt for key and (re)locks it past the threshold.
func (l *Lockout) Fail(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	for k, a := range l.attempt {
		if now.Sub(a.lastTry) > lockoutWindow {
			delete(l.attempt, k)
		}
	}
	a := l.attempt[key]
	a.failures++
	a.lastTry = now
	if a.failures >= lockThreshold {
		penalty := lockBase + lockGrowth*time.Duration(a.failures/lockThreshold-1)
		if penalty > maxLockPenalty {
			penalty = maxLockPenalty
		}
		a.lockedTo = now.Add(penalty)
	}
	l.attempt[key] = a
}

// Reset clears the failure count after a successful sign-in.
func (l *Lockout) Reset(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.attempt, key)
}
