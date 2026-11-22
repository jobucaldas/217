package passwordauth

import (
	"testing"
	"time"
)

func TestHashAndVerify(t *testing.T) {
	hash, err := Hash("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	if !Verify("correct horse battery staple", hash) {
		t.Fatal("correct password rejected")
	}
	if Verify("wrong password entirely", hash) {
		t.Fatal("wrong password accepted")
	}
	if Verify("anything", "not-a-hash") || Verify("anything", "") {
		t.Fatal("malformed hashes must never verify")
	}
	// A second hash of the same password must use a different salt.
	again, err := Hash("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	if again == hash {
		t.Fatal("salt reuse: identical hashes for the same password")
	}
}

func TestValidPasswordPolicy(t *testing.T) {
	cases := []struct {
		password string
		want     bool
	}{
		{"short1", false},                        // too short
		{"0123456789abcde", true},                // exactly 15
		{"0123456789abcdef", true},               // 16
		{"_contraseña_muy_larga_y_segura", true}, // Unicode, no composition rules
		{"Password123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890", true},   // exactly 128
		{"Password1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901", false}, // 129
		{"password12345678", false},     // blocklisted
		{"Correct-Horse-Battery", true}, // long, not blocklisted
	}
	for _, c := range cases {
		if got := ValidPassword(c.password); got != c.want {
			t.Fatalf("ValidPassword(%q) = %v, want %v", c.password, got, c.want)
		}
	}
}

func TestLockoutAfterFifteenFailures(t *testing.T) {
	l := NewLockout()
	if l.Locked("ip") {
		t.Fatal("fresh key must not be locked")
	}
	for i := 0; i < lockThreshold; i++ {
		l.Fail("ip")
	}
	if !l.Locked("ip") {
		t.Fatal("15 failures must lock the address")
	}
	if got := l.RetryAfter(); got <= 0 || got > lockBase+time.Second {
		t.Fatalf("first lockout should be ~30m, got %v", got)
	}
	// A different key is unaffected.
	if l.Locked("other") {
		t.Fatal("lockout leaked to another key")
	}
	// Success resets.
	l.Reset("ip")
	if l.Locked("ip") {
		t.Fatal("reset must clear the lockout")
	}
}

func TestLockoutGrowsByOneHourPerRepeat(t *testing.T) {
	l := NewLockout()
	for i := 0; i < lockThreshold*2; i++ {
		l.Fail("ip")
	}
	// 30 failures = two locks: 30m + 1h = 90m.
	got := l.RetryAfter()
	if got < time.Hour+29*time.Minute || got > time.Hour+30*time.Minute+time.Second {
		t.Fatalf("second lock should be ~1h30m, got %v", got)
	}
}
