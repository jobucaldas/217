// Package fieldcrypt seals personal data before it reaches the database and
// derives blind indexes for the few sealed values that are looked up.
//
// Sealed values are AES-256-GCM: version (1 byte) | key id (4) | nonce (12) |
// ciphertext+tag. The version and key id are authenticated with the caller's
// context string (table, column and row owner), so a sealed value copied to
// another row or user does not open. Blind indexes are HMAC-SHA256 over a
// purpose label and the value.
package fieldcrypt

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hkdf"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
)

const (
	version   byte = 1
	keySize        = 32
	idSize         = 4
	nonceSize      = 12
	header         = 1 + idSize
)

// ErrUnknownKey means the value was sealed with a key this keyring lacks.
var ErrUnknownKey = errors.New("fieldcrypt: sealed with an unknown key")

type keyID [idSize]byte

// Keyring seals with its primary key and opens with the primary or any previous key.
type Keyring struct {
	primary  keyID
	aeads    map[keyID]cipher.AEAD
	indexKey []byte
	previous int
}

// ParseKey decodes a 32-byte key given as base64 (standard or URL alphabet,
// padded or not) or as 64 hex characters.
func ParseKey(s string) ([]byte, error) {
	s = strings.TrimSpace(s)
	if len(s) == 2*keySize {
		if b, err := hex.DecodeString(s); err == nil {
			return b, nil
		}
	}
	for _, enc := range []*base64.Encoding{base64.StdEncoding, base64.RawStdEncoding, base64.URLEncoding, base64.RawURLEncoding} {
		if b, err := enc.DecodeString(s); err == nil {
			if len(b) != keySize {
				return nil, fmt.Errorf("fieldcrypt: key must be %d bytes, got %d", keySize, len(b))
			}
			return b, nil
		}
	}
	return nil, fmt.Errorf("fieldcrypt: key must be base64 or hex encoded")
}

// FromStrings builds a keyring from an encoded primary key and a list of
// previous keys separated by commas or whitespace (empty for none).
func FromStrings(primary, previous string) (*Keyring, error) {
	p, err := ParseKey(primary)
	if err != nil {
		return nil, err
	}
	var old [][]byte
	for _, s := range strings.FieldsFunc(previous, func(r rune) bool { return r == ',' || r == ' ' || r == '\n' || r == '\t' }) {
		k, err := ParseKey(s)
		if err != nil {
			return nil, fmt.Errorf("previous key: %w", err)
		}
		old = append(old, k)
	}
	return New(p, old...)
}

// New builds a keyring. Values are sealed with primary; previous keys only open.
func New(primary []byte, previous ...[]byte) (*Keyring, error) {
	k := &Keyring{aeads: map[keyID]cipher.AEAD{}}
	for i, raw := range append([][]byte{primary}, previous...) {
		if len(raw) != keySize {
			return nil, fmt.Errorf("fieldcrypt: key must be %d bytes, got %d", keySize, len(raw))
		}
		id, aead, err := deriveSealer(raw)
		if err != nil {
			return nil, err
		}
		if _, dup := k.aeads[id]; dup {
			continue // a previous key equal to one already loaded adds nothing
		}
		k.aeads[id] = aead
		if i == 0 {
			k.primary = id
			k.indexKey, err = hkdf.Key(sha256.New, raw, nil, "217 blind index v1", keySize)
			if err != nil {
				return nil, err
			}
		} else {
			k.previous++
		}
	}
	return k, nil
}

func deriveSealer(raw []byte) (keyID, cipher.AEAD, error) {
	var id keyID
	idBytes, err := hkdf.Key(sha256.New, raw, nil, "217 key id v1", idSize)
	if err != nil {
		return id, nil, err
	}
	copy(id[:], idBytes)
	sealKey, err := hkdf.Key(sha256.New, raw, nil, "217 field seal v1", keySize)
	if err != nil {
		return id, nil, err
	}
	block, err := aes.NewCipher(sealKey)
	if err != nil {
		return id, nil, err
	}
	aead, err := cipher.NewGCM(block)
	return id, aead, err
}

// Rotating reports whether previous keys are configured, so values sealed
// with them should be resealed under the primary key.
func (k *Keyring) Rotating() bool { return k.previous > 0 }

// Seal encrypts plaintext bound to context.
func (k *Keyring) Seal(plaintext []byte, context string) []byte {
	out := make([]byte, header+nonceSize, header+nonceSize+len(plaintext)+16)
	out[0] = version
	copy(out[1:header], k.primary[:])
	if _, err := rand.Read(out[header:]); err != nil {
		panic(fmt.Sprintf("fieldcrypt: read random nonce: %v", err))
	}
	return k.aeads[k.primary].Seal(out, out[header:], plaintext, additional(out[:header], context))
}

// SealString seals a string.
func (k *Keyring) SealString(s, context string) []byte { return k.Seal([]byte(s), context) }

// Open decrypts a sealed value; it fails if context differs from the one used to seal.
func (k *Keyring) Open(sealed []byte, context string) ([]byte, error) {
	if len(sealed) < header+nonceSize+16 || sealed[0] != version {
		return nil, errors.New("fieldcrypt: malformed sealed value")
	}
	var id keyID
	copy(id[:], sealed[1:header])
	aead, ok := k.aeads[id]
	if !ok {
		return nil, ErrUnknownKey
	}
	nonce := sealed[header : header+nonceSize]
	plain, err := aead.Open(nil, nonce, sealed[header+nonceSize:], additional(sealed[:header], context))
	if err != nil {
		return nil, errors.New("fieldcrypt: sealed value failed authentication")
	}
	return plain, nil
}

// OpenString opens a value sealed with SealString.
func (k *Keyring) OpenString(sealed []byte, context string) (string, error) {
	b, err := k.Open(sealed, context)
	return string(b), err
}

// Current reports whether sealed was produced by the primary key.
func (k *Keyring) Current(sealed []byte) bool {
	return len(sealed) >= header && sealed[0] == version && bytes.Equal(sealed[1:header], k.primary[:])
}

// Known reports whether some key in the keyring can open sealed.
func (k *Keyring) Known(sealed []byte) bool {
	if len(sealed) < header || sealed[0] != version {
		return false
	}
	var id keyID
	copy(id[:], sealed[1:header])
	_, ok := k.aeads[id]
	return ok
}

// Index is a deterministic, keyed digest of value for equality lookups.
// purpose separates indexes so equal values in different columns differ.
func (k *Keyring) Index(purpose, value string) []byte {
	mac := hmac.New(sha256.New, k.indexKey)
	mac.Write([]byte(purpose))
	mac.Write([]byte{0})
	mac.Write([]byte(value))
	return mac.Sum(nil)
}

func additional(hdr []byte, context string) []byte {
	return append(append([]byte{}, hdr...), context...)
}
