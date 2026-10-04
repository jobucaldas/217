package fieldcrypt

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"testing"
)

func newKey(t *testing.T) []byte {
	t.Helper()
	k := make([]byte, keySize)
	if _, err := rand.Read(k); err != nil {
		t.Fatal(err)
	}
	return k
}

func TestSealOpenRoundTripAndContextBinding(t *testing.T) {
	k, err := New(newKey(t))
	if err != nil {
		t.Fatal(err)
	}
	sealed := k.SealString("took it late", "entries|u1|2026-10-01")
	if bytes.Contains(sealed, []byte("took it late")) {
		t.Fatal("plaintext visible in sealed value")
	}
	if got, err := k.OpenString(sealed, "entries|u1|2026-10-01"); err != nil || got != "took it late" {
		t.Fatalf("open = %q, %v", got, err)
	}
	if _, err := k.Open(sealed, "entries|u2|2026-10-01"); err == nil {
		t.Fatal("value opened under another row's context")
	}
	tampered := append([]byte{}, sealed...)
	tampered[len(tampered)-1] ^= 1
	if _, err := k.Open(tampered, "entries|u1|2026-10-01"); err == nil {
		t.Fatal("tampered value opened")
	}
	if bytes.Equal(sealed, k.SealString("took it late", "entries|u1|2026-10-01")) {
		t.Fatal("sealing must be randomized")
	}
}

func TestRotationOpensOldValuesAndSealsWithPrimary(t *testing.T) {
	oldKey, newKeyBytes := newKey(t), newKey(t)
	old, _ := New(oldKey)
	sealedOld := old.SealString("v", "ctx")

	rotated, err := New(newKeyBytes, oldKey)
	if err != nil {
		t.Fatal(err)
	}
	if !rotated.Rotating() || rotated.Current(sealedOld) || !rotated.Known(sealedOld) {
		t.Fatal("old value should be known but not current")
	}
	if got, err := rotated.OpenString(sealedOld, "ctx"); err != nil || got != "v" {
		t.Fatalf("open old = %q, %v", got, err)
	}
	if !rotated.Current(rotated.SealString("v", "ctx")) {
		t.Fatal("new values must use the primary key")
	}

	fresh, _ := New(newKeyBytes)
	if _, err := fresh.Open(sealedOld, "ctx"); !errors.Is(err, ErrUnknownKey) {
		t.Fatalf("missing old key: got %v, want ErrUnknownKey", err)
	}
}

func TestIndexIsKeyedAndPurposeSeparated(t *testing.T) {
	a, _ := New(newKey(t))
	b, _ := New(newKey(t))
	if !bytes.Equal(a.Index("email", "x@example.com"), a.Index("email", "x@example.com")) {
		t.Fatal("index must be deterministic")
	}
	if bytes.Equal(a.Index("email", "x@example.com"), a.Index("invite", "x@example.com")) {
		t.Fatal("purposes must not collide")
	}
	if bytes.Equal(a.Index("email", "x@example.com"), b.Index("email", "x@example.com")) {
		t.Fatal("index must depend on the key")
	}
}

func TestParseKeyFormats(t *testing.T) {
	raw := newKey(t)
	for _, s := range []string{
		base64.StdEncoding.EncodeToString(raw),
		base64.RawURLEncoding.EncodeToString(raw),
		hex.EncodeToString(raw),
		" " + base64.StdEncoding.EncodeToString(raw) + "\n",
	} {
		got, err := ParseKey(s)
		if err != nil || !bytes.Equal(got, raw) {
			t.Fatalf("ParseKey(%q) = %x, %v", s, got, err)
		}
	}
	for _, s := range []string{"", "short", base64.StdEncoding.EncodeToString(raw[:16])} {
		if _, err := ParseKey(s); err == nil {
			t.Fatalf("ParseKey(%q) accepted", s)
		}
	}
	if _, err := FromStrings(base64.StdEncoding.EncodeToString(raw), "nope"); err == nil {
		t.Fatal("bad previous key accepted")
	}
}
