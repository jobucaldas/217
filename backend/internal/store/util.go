package store

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"

	"217/backend/internal/model"
)

func generateID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(fmt.Sprintf("failed to read random bytes: %v", err))
	}
	return hex.EncodeToString(b)
}

func generateAPIKey() string {
	return "217_" + generateID()
}

func hashString(value string) string {
	h := sha256.Sum256([]byte(value))
	return hex.EncodeToString(h[:])
}

func normalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

func sanitizeUser(user *model.User) *model.User {
	if user == nil {
		return nil
	}
	copy := *user
	copy.APIKey = ""
	copy.PasswordHash = ""
	return &copy
}
