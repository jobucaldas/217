package handler

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Simple fixed-window IP rate limiter for auth endpoints.
type ipRateLimiter struct {
	mu     sync.Mutex
	limit  int
	window time.Duration
	hits   map[string]int
	resets map[string]time.Time
}

func newIPRateLimiter(limit int, window time.Duration) *ipRateLimiter {
	if limit <= 0 {
		limit = 30
	}
	if window <= 0 {
		window = time.Minute
	}
	return &ipRateLimiter{
		limit:  limit,
		window: window,
		hits:   map[string]int{},
		resets: map[string]time.Time{},
	}
}

func (l *ipRateLimiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	if reset, ok := l.resets[key]; !ok || now.After(reset) {
		l.resets[key] = now.Add(l.window)
		l.hits[key] = 1
		return true
	}
	l.hits[key]++
	return l.hits[key] <= l.limit
}

// clientIP keys rate limits by caller address. Behind the bundled Caddy the
// right-most X-Forwarded-For entry is the one our proxy appended; earlier
// entries are client-supplied and could be rotated to dodge the limit.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		if ip := strings.TrimSpace(parts[len(parts)-1]); ip != "" {
			return ip
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
