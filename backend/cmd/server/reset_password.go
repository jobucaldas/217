package main

import (
	"bufio"
	"fmt"
	"io"
	"strings"

	"217/backend/internal/model"
	"217/backend/internal/passwordauth"
)

type passwordResetStore interface {
	GetUserByEmail(string) (*model.User, error)
	ResetPasswordCredential(string, string) error
}

func resetPassword(s passwordResetStore, email string, input io.Reader, output io.Writer) error {
	email = strings.ToLower(strings.TrimSpace(email))
	user, err := s.GetUserByEmail(email)
	if err != nil {
		return fmt.Errorf("finding account: %w", err)
	}
	scanner := bufio.NewScanner(input)
	if !scanner.Scan() {
		if scanner.Err() != nil {
			return fmt.Errorf("reading password: %w", scanner.Err())
		}
		return fmt.Errorf("password required on stdin")
	}
	password := scanner.Text()
	if !passwordauth.ValidPassword(password) {
		return fmt.Errorf("password must be 15-128 characters and not blocklisted")
	}
	hash, err := passwordauth.Hash(password)
	if err != nil {
		return fmt.Errorf("hashing password: %w", err)
	}
	if err := s.ResetPasswordCredential(user.ID, hash); err != nil {
		return fmt.Errorf("resetting password: %w", err)
	}
	_, err = fmt.Fprintf(output, "password reset for %s\nrestart the server to end cached sync sessions immediately\n", email)
	return err
}
