package store

import (
	"testing"
	"time"
)

func TestFormatDate_Time(t *testing.T) {
	tm := time.Date(2026, 9, 1, 15, 30, 45, 0, time.UTC)
	out := formatDate(tm)
	if out != "2026-09-01" {
		t.Fatalf("expected 2026-09-01, got %s", out)
	}
}
