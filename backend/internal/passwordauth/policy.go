package passwordauth

import "unicode/utf8"

// Min and MaxPasswordLen bound accepted passwords, in characters (runes).
// Unicode is allowed and no composition rules are imposed; the blocklist
// (WeakPassword) rejects the most-chosen ones.
const (
	MinPasswordLen = 15
	MaxPasswordLen = 128
)

// ValidPassword reports whether password fits the policy: 15-128 characters
// (runes), Unicode allowed, no composition rules, and not on the blocklist.
func ValidPassword(password string) bool {
	n := utf8.RuneCountInString(password)
	if n < MinPasswordLen || n > MaxPasswordLen {
		return false
	}
	return !WeakPassword(password)
}
