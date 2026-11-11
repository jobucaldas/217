package passwordauth

import (
	"context"
	"sync"
	"time"
)

// accountDelay tarpits repeated password failures for one account: each
// recent failure adds 500 ms of waiting before a WRONG attempt is answered
// (capped at 5 s, reset after 15 quiet minutes). It never locks the account
// — a correct password is answered at once and clears the delay. Attempts
// for one account run one at a time through a small bounded queue so
// parallel guesses cannot bypass the throttle; beyond the queue the request
// is refused (overflow only, never a lock of the account itself).
const (
	delayStep  = 500 * time.Millisecond
	delayMax   = 5 * time.Second
	delayReset = 15 * time.Minute
	delayQueue = 4 // attempts held per account; beyond that 429
)

// Delay serializes and tarpits attempts per key (per account).
type Delay struct {
	mu    sync.Mutex
	state map[string]*delayState
	step  time.Duration
	max   time.Duration
	reset time.Duration
	queue int
}

type delayState struct {
	failures int
	lastTry  time.Time
	gate     chan struct{} // one slot: the attempt currently served
	holders  int           // attempts in or waiting for the gate
}

// NewDelay returns a ready-to-use delay tracker.
func NewDelay() *Delay {
	return NewDelayWith(delayStep, delayMax, delayReset, delayQueue)
}

// NewDelayWith builds a tracker with custom timings (tests).
func NewDelayWith(step, max, reset time.Duration, queue int) *Delay {
	return &Delay{
		state: map[string]*delayState{},
		step:  step,
		max:   max,
		reset: reset,
		queue: queue,
	}
}

// Enter serializes the caller's attempt for key: it blocks until its turn
// (bounded queue, honoring ctx) and returns the release function to call
// when the attempt is done. ok=false means the queue was full — the caller
// answers 429; the account itself is not locked.
func (d *Delay) Enter(key string, ctx context.Context) (release func(), ok bool) {
	d.mu.Lock()
	a, exists := d.state[key]
	if !exists {
		a = &delayState{}
		d.state[key] = a
	}
	if a.holders >= d.queue {
		d.mu.Unlock()
		return nil, false
	}
	a.holders++
	if a.gate == nil {
		a.gate = make(chan struct{}, 1)
	}
	gate := a.gate
	d.mu.Unlock()
	select {
	case gate <- struct{}{}:
		return func() {
			<-gate
			d.mu.Lock()
			a.holders--
			d.mu.Unlock()
		}, true
	case <-ctx.Done():
		d.mu.Lock()
		a.holders--
		d.mu.Unlock()
		return nil, false
	}
}

// Wait returns how long a WRONG attempt for key must be held before it is
// answered (0 = at once). The caller sleeps; Fail and Reset update the
// state. A correct password never waits: it skips this and calls Reset.
func (d *Delay) Wait(key string) time.Duration {
	d.mu.Lock()
	defer d.mu.Unlock()
	a, ok := d.state[key]
	if !ok || time.Since(a.lastTry) > d.reset {
		return 0
	}
	wait := time.Duration(a.failures) * d.step
	if wait > d.max {
		wait = d.max
	}
	return wait
}

// Fail records a failed attempt for key.
func (d *Delay) Fail(key string) {
	d.mu.Lock()
	defer d.mu.Unlock()
	now := time.Now()
	a, ok := d.state[key]
	if !ok {
		a = &delayState{}
		d.state[key] = a
	} else if now.Sub(a.lastTry) > d.reset {
		a.failures = 0 // quiet period: start the count over
	}
	a.failures++
	a.lastTry = now
}

// Reset clears the failure count after a successful sign-in.
func (d *Delay) Reset(key string) {
	d.mu.Lock()
	defer d.mu.Unlock()
	delete(d.state, key)
}
