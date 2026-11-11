// Package mailer sends the few transactional emails password auth needs
// (address verification). SMTP_HOST empty means mail features are off.
package mailer

import (
	"fmt"
	"log"
	"net/smtp"
	"strings"
)

// Mailer sends one message to one address. Bodies carry only the code or
// link and a minimal sentence — nothing revealing about the account.
type Mailer interface {
	SendVerification(to, code string) error
}

// Config comes from the environment; everything is optional.
type Config struct {
	Host     string // SMTP_HOST; empty disables mail
	Port     string // SMTP_PORT (default 587)
	User     string // SMTP_USER
	Password string // SMTP_PASS
	From     string // SMTP_FROM
}

// Enabled reports whether mail features are on.
func (c Config) Enabled() bool { return c.Host != "" }

// New returns an SMTP mailer when configured, else the log mailer.
func New(cfg Config) Mailer {
	if !cfg.Enabled() {
		return LogMailer{}
	}
	if cfg.Port == "" {
		cfg.Port = "587"
	}
	if cfg.From == "" {
		cfg.From = "217@" + cfg.Host
	}
	return SMTPMailer{cfg: cfg}
}

// LogMailer "sends" by logging: development and self-hosted setups without
// SMTP. The code is printed, so it is only for non-production use.
type LogMailer struct{}

func (LogMailer) SendVerification(to, code string) error {
	log.Printf("mailer: verification for %s: %s", to, code)
	return nil
}

// SMTPMailer sends via net/smtp with STARTTLS when the server offers it.
type SMTPMailer struct {
	cfg Config
}

func (m SMTPMailer) SendVerification(to, code string) error {
	addr := m.cfg.Host + ":" + m.cfg.Port
	subject := "217 verification code"
	body := "Your 217 verification code is: " + code + "\n"
	msg := strings.Join([]string{
		"From: " + m.cfg.From,
		"To: " + to,
		"Subject: " + subject,
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=utf-8",
		"",
		body,
	}, "\r\n")
	var auth smtp.Auth
	if m.cfg.User != "" {
		auth = smtp.PlainAuth("", m.cfg.User, m.cfg.Password, m.cfg.Host)
	}
	if err := smtp.SendMail(addr, auth, m.cfg.From, []string{to}, []byte(msg)); err != nil {
		return fmt.Errorf("sending verification mail: %w", err)
	}
	return nil
}
