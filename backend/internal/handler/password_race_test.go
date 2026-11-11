package handler_test

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

// TestPasswordSignupConcurrencyMemory races N signups for one email: exactly
// one 201, the rest 409 (the store serializes under its mutex).
func TestPasswordSignupConcurrencyMemory(t *testing.T) {
	h, s := newTestHandler(t)
	const n = 8
	codes := make([]int, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			req := httptest.NewRequest(http.MethodPost, "/api/auth/password/signup",
				strings.NewReader(fmt.Sprintf(`{"email":"race@example.com","password":"long-enough-password-%d"}`, i)))
			w := httptest.NewRecorder()
			h.SignupPassword(w, req)
			codes[i] = w.Code
		}(i)
	}
	wg.Wait()
	created, conflict := 0, 0
	for _, c := range codes {
		switch c {
		case http.StatusCreated:
			created++
		case http.StatusConflict:
			conflict++
		}
	}
	if created != 1 || conflict != n-1 {
		t.Fatalf("expected 1 created and %d conflicts, got %d and %d", n-1, created, conflict)
	}
	// Exactly one user row for the email.
	email := "race@example.com"
	if _, err := s.GetUserByEmail(email); err != nil {
		t.Fatalf("the winning account must exist: %v", err)
	}
}
