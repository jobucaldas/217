// Package passwordauth implements first-party email+password sign-in:
// Argon2id hashing, the common-password blocklist and the lockout policy.
package passwordauth

import (
	"crypto/rand"
	"crypto/subtle"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"golang.org/x/crypto/argon2"
)

const (
	argonTime    = 1
	argonMemory  = 64 * 1024 // KiB
	argonThreads = 2
	argonKeyLen  = 32
	argonSaltLen = 16
)

// ErrWrongPassword reports a failed password check (any mismatch cause).
var ErrWrongPassword = errors.New("invalid email or password")

// dummyHash is a valid hash of an unguessable string, checked when the
// account does not exist so responses take the same time either way.
var dummyHash = func() string {
	h, err := Hash("A0dummy" + "hash" + "value" + "for" + "timing")
	if err != nil {
		panic(err) // fixed inputs always hash
	}
	return h
}()

// DummyVerify burns one Argon2id verification without a real credential.
func DummyVerify() { Verify("definitely-not-the-password", dummyHash) }

// NewVerificationCode returns a random 8-character numeric code for address
// verification (email bodies carry only this).
func NewVerificationCode() (string, error) {
	const digits = "0123456789"
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	out := make([]byte, len(b))
	for i, c := range b {
		out[i] = digits[int(c)%len(digits)]
	}
	return string(out), nil
}

// Hash derives an Argon2id hash of password with a fresh random salt,
// encoded as `argon2id$<t>$<m>$<p>$<salt>$<hash>` (base64, no padding).
func Hash(password string) (string, error) {
	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("generating salt: %w", err)
	}
	key := argon2.IDKey([]byte(password), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	return encodeHash(argonTime, argonMemory, argonThreads, salt, key), nil
}

// Verify reports whether password matches a hash produced by Hash. Unknown
// formats are rejected, never accepted.
func Verify(password, encoded string) bool {
	t, m, p, salt, want, ok := decodeHash(encoded)
	if !ok {
		return false
	}
	got := argon2.IDKey([]byte(password), salt, t, m, p, uint32(len(want)))
	return subtle.ConstantTimeCompare(got, want) == 1
}

func encodeHash(t, m uint32, p uint8, salt, key []byte) string {
	return "argon2id$" + strconv.Itoa(int(t)) + "$" + strconv.Itoa(int(m)) + "$" + strconv.Itoa(int(p)) + "$" +
		base64RawStd(salt) + "$" + base64RawStd(key)
}

func base64RawStd(b []byte) string {
	const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	out := make([]byte, 0, (len(b)*8+5)/6)
	var buf, bits uint32
	for _, c := range b {
		buf = buf<<8 | uint32(c)
		bits += 8
		for bits >= 6 {
			bits -= 6
			out = append(out, alphabet[buf>>bits&0x3f])
		}
	}
	if bits > 0 {
		out = append(out, alphabet[buf<<uint(6-bits)&0x3f])
	}
	return string(out)
}

func decodeHash(encoded string) (t, m uint32, p uint8, salt, key []byte, ok bool) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[0] != "argon2id" {
		return 0, 0, 0, nil, nil, false
	}
	ti, err1 := strconv.Atoi(parts[1])
	mi, err2 := strconv.Atoi(parts[2])
	pi, err3 := strconv.Atoi(parts[3])
	if err1 != nil || err2 != nil || err3 != nil || ti < 1 || mi < 1 || pi < 1 {
		return 0, 0, 0, nil, nil, false
	}
	salt, ok1 := decodeBase64RawStd(parts[4])
	key, ok2 := decodeBase64RawStd(parts[5])
	if !ok1 || !ok2 || len(salt) == 0 || len(key) < argonKeyLen {
		return 0, 0, 0, nil, nil, false
	}
	return uint32(ti), uint32(mi), uint8(pi), salt, key, true
}

func decodeBase64RawStd(s string) ([]byte, bool) {
	const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	if s == "" {
		return nil, false
	}
	var out []byte
	var buf, bits uint32
	for _, c := range []byte(s) {
		idx := strings.IndexByte(alphabet, c)
		if idx < 0 {
			return nil, false
		}
		buf = buf<<6 | uint32(idx)
		bits += 6
		if bits >= 8 {
			bits -= 8
			out = append(out, byte(buf>>bits))
		}
	}
	return out, true
}
