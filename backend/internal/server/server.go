package server

import (
	"crypto/tls"
	"encoding/base64"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"slices"
	"strings"
	"time"

	"217/backend/internal/auth"
	"217/backend/internal/fieldcrypt"
	"217/backend/internal/handler"
	"217/backend/internal/reminder"
	"217/backend/internal/store"
)

type PushConfig struct {
	PublicKey  string
	PrivateKey string
	Subject    string
}

type WorkOSConfig struct {
	APIKey     string
	ClientID   string
	AppBaseURL string
}

func ValidatePushConfig(push PushConfig) (PushConfig, error) {
	if push.PublicKey == "" && push.PrivateKey == "" {
		return PushConfig{}, nil
	}
	if push.PublicKey == "" || push.PrivateKey == "" {
		return PushConfig{}, fmt.Errorf("both VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY are required")
	}
	publicKey, publicErr := base64.RawURLEncoding.DecodeString(strings.TrimRight(push.PublicKey, "="))
	privateKey, privateErr := base64.RawURLEncoding.DecodeString(strings.TrimRight(push.PrivateKey, "="))
	if publicErr != nil || privateErr != nil || len(publicKey) != 65 || len(privateKey) != 32 {
		return PushConfig{}, fmt.Errorf("VAPID keys are not a valid P-256 key pair encoding")
	}
	subject, err := url.Parse(push.Subject)
	if err != nil || (subject.Scheme != "mailto" && subject.Scheme != "https") || subject.Opaque == "" && subject.Host == "" {
		return PushConfig{}, fmt.Errorf("VAPID_SUBJECT must be a mailto: or https: contact")
	}
	return push, nil
}

// Config is everything the API needs to start.
type Config struct {
	Addr        string
	DatabaseURL string
	AppBaseURL  string
	// AllowedOrigins is a comma-separated list of extra public origins for browser sign-in.
	AllowedOrigins string
	Push           PushConfig
	WorkOS         WorkOSConfig
	// Keyring seals personal data at rest; required with a database.
	Keyring *fieldcrypt.Keyring
	// PrivacyContact (email or URL) is shown in the app's privacy notice.
	PrivacyContact string
	// TLSCertFile and TLSKeyFile make the API serve HTTPS (e.g. to its proxy).
	TLSCertFile string
	TLSKeyFile  string
}

// Run starts the API and blocks until it stops.
func Run(cfg Config) error {
	appBaseURL, err := auth.ValidateAppBaseURL(cfg.AppBaseURL)
	if err != nil {
		return err
	}
	if cfg.WorkOS.AppBaseURL != "" {
		workosBaseURL, validateErr := auth.ValidateAppBaseURL(cfg.WorkOS.AppBaseURL)
		if validateErr != nil {
			return validateErr
		}
		if appBaseURL != "" && appBaseURL != workosBaseURL {
			return fmt.Errorf("APP_BASE_URL must be consistent across server and WorkOS OAuth configuration")
		}
		appBaseURL = workosBaseURL
	}
	cfg.WorkOS.AppBaseURL = appBaseURL
	allowedOrigins, err := auth.ParseAllowedOrigins(appBaseURL, cfg.AllowedOrigins)
	if err != nil {
		return err
	}
	push, err := ValidatePushConfig(cfg.Push)
	if err != nil {
		return err
	}
	if (cfg.TLSCertFile == "") != (cfg.TLSKeyFile == "") {
		return fmt.Errorf("TLS_CERT_FILE and TLS_KEY_FILE must be set together")
	}

	var s store.Store
	if cfg.DatabaseURL != "" {
		if cfg.Keyring == nil {
			return fmt.Errorf("DATA_ENCRYPTION_KEY is required with a database")
		}
		if !databaseTLSVerified(cfg.DatabaseURL) {
			log.Println("warning: the database connection is not verified TLS; set sslmode=verify-full (see README)")
		}
		log.Println("connecting to postgres")
		pg, err := store.NewPGStore(cfg.DatabaseURL, cfg.Keyring)
		if err != nil {
			return fmt.Errorf("connect to database: %w", err)
		}
		if err := pg.Prepare(); err != nil {
			pg.Close()
			return err
		}
		s = pg
		log.Println("connected to postgres")
	} else {
		log.Println("using in-memory store")
		s = store.NewMemoryStore()
	}
	defer s.Close()

	h := handler.NewWithVAPID(s, push.PublicKey)
	h.SetAppBaseURL(appBaseURL)
	h.SetAllowedOrigins(allowedOrigins)
	h.SetPrivacyContact(cfg.PrivacyContact)

	stopJanitor := make(chan struct{})
	defer close(stopJanitor)
	go purgeExpired(s, stopJanitor)
	if ttl := parseSessionTTL(); ttl > 0 {
		h.SetSessionDuration(ttl)
	}
	if cfg.WorkOS.ClientID != "" && cfg.WorkOS.AppBaseURL != "" {
		provider, providerErr := auth.NewWorkOSOAuth(cfg.WorkOS.APIKey, cfg.WorkOS.ClientID, cfg.WorkOS.AppBaseURL)
		if providerErr != nil {
			log.Printf("workos oauth disabled: %v", providerErr)
		} else {
			provider.SetAllowedOrigins(allowedOrigins)
			h.SetOAuthProvider(provider)
			if cfg.WorkOS.APIKey == "" {
				log.Println("workos oauth enabled (PKCE public exchange)")
			} else {
				log.Println("workos oauth enabled (PKCE public exchange; API key is not sent on code exchange)")
			}
		}
	} else {
		log.Println("workos oauth disabled: missing WORKOS_CLIENT_ID or APP_BASE_URL")
	}
	if push.PublicKey != "" && push.PrivateKey != "" {
		stop := make(chan struct{})
		defer close(stop)
		service := reminder.Service{Store: s, Sender: reminder.WebPushSender{
			PublicKey: push.PublicKey, PrivateKey: push.PrivateKey, Subject: push.Subject,
		}}
		go service.Run(stop)
		log.Println("web push reminder scheduler enabled")
	} else {
		log.Println("web push reminders disabled: configure VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY")
	}

	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	mux.HandleFunc("GET /api/auth/config", h.AuthConfig)
	mux.HandleFunc("GET /api/auth/session", h.CurrentSession)
	mux.HandleFunc("POST /api/auth/logout", h.Logout)
	mux.HandleFunc("POST /api/auth/register", h.Register)
	mux.HandleFunc("POST /api/auth/login", h.Login)
	mux.HandleFunc("GET /api/auth/workos", h.StartWorkOSOAuth)
	mux.HandleFunc("GET /api/auth/workos/callback", h.WorkOSOAuthCallback)
	mux.HandleFunc("POST /api/auth/workos/exchange", h.ExchangeWorkOS)

	mux.HandleFunc("GET /api/entries", h.ConsentMiddleware(h.ListEntries))
	mux.HandleFunc("GET /api/entries/{date}", h.ConsentMiddleware(h.GetEntry))
	mux.HandleFunc("POST /api/entries/{date}", h.ConsentMiddleware(h.UpsertEntry))
	mux.HandleFunc("DELETE /api/entries/{date}", h.ConsentMiddleware(h.DeleteEntry))
	mux.HandleFunc("GET /api/stats", h.ConsentMiddleware(h.GetStats))

	// Rights that stay reachable before (or instead of) consenting.
	mux.HandleFunc("DELETE /api/account", h.AuthMiddleware(h.DeleteAccount))
	mux.HandleFunc("PUT /api/account/consent", h.AuthMiddleware(h.RecordConsent))
	mux.HandleFunc("GET /api/account/export", h.AuthMiddleware(h.ExportAccount))
	mux.HandleFunc("PUT /api/account/role", h.ConsentMiddleware(h.SetRole))
	mux.HandleFunc("PUT /api/account/stage", h.ConsentMiddleware(h.SetStage))
	mux.HandleFunc("GET /api/cycle", h.ConsentMiddleware(h.GetCycle))
	mux.HandleFunc("GET /api/partner-alerts", h.ConsentMiddleware(h.GetPartnerAlerts))
	mux.HandleFunc("PUT /api/partner-alerts", h.ConsentMiddleware(h.UpsertPartnerAlerts))
	mux.HandleFunc("GET /api/share", h.ConsentMiddleware(h.GetShare))
	mux.HandleFunc("POST /api/share/enable", h.ConsentMiddleware(h.EnableShare))
	mux.HandleFunc("POST /api/share/revoke", h.ConsentMiddleware(h.RevokeShare))
	mux.HandleFunc("POST /api/share/accept", h.ConsentMiddleware(h.AcceptShare))
	mux.HandleFunc("GET /api/inbox", h.ConsentMiddleware(h.ListInbox))
	mux.HandleFunc("POST /api/inbox/{id}/read", h.ConsentMiddleware(h.MarkInboxNoteRead))
	mux.HandleFunc("POST /api/partner-notes", h.ConsentMiddleware(h.CreatePartnerNote))

	mux.HandleFunc("GET /api/reminders/preferences", h.ConsentMiddleware(h.GetReminderPreference))
	mux.HandleFunc("PUT /api/reminders/preferences", h.ConsentMiddleware(h.UpsertReminderPreference))
	mux.HandleFunc("GET /api/reminders/vapid-public-key", h.ConsentMiddleware(h.VAPIDPublicKey))
	mux.HandleFunc("POST /api/reminders/subscriptions", h.ConsentMiddleware(h.SavePushSubscription))
	mux.HandleFunc("DELETE /api/reminders/subscriptions", h.ConsentMiddleware(h.DeletePushSubscription))

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           secureHeaders(limitBody(corsMiddleware(mux, allowedOrigins))),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    64 << 10,
	}
	if cfg.TLSCertFile != "" {
		srv.TLSConfig = &tls.Config{MinVersion: tls.VersionTLS12}
		log.Printf("server starting on %s (TLS)", cfg.Addr)
		return srv.ListenAndServeTLS(cfg.TLSCertFile, cfg.TLSKeyFile)
	}
	log.Printf("server starting on %s", cfg.Addr)
	return srv.ListenAndServe()
}

// purgeExpired applies the retention rules hourly (see Store.PurgeExpired).
func purgeExpired(s store.Store, stop <-chan struct{}) {
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	for {
		if err := s.PurgeExpired(time.Now()); err != nil {
			log.Printf("retention purge: %v", err)
		}
		select {
		case <-ticker.C:
		case <-stop:
			return
		}
	}
}

// maxBodyBytes bounds request bodies; the largest legitimate one is a day note.
const maxBodyBytes = 64 << 10

func limitBody(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
		}
		next.ServeHTTP(w, r)
	})
}

// secureHeaders keeps API responses (health data) out of caches and stops
// browsers from sniffing or framing them, whatever proxy sits in front.
func secureHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Cache-Control", "no-store")
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
		next.ServeHTTP(w, r)
	})
}

// databaseTLSVerified reports whether a postgres URL asks for a verified TLS connection.
func databaseTLSVerified(databaseURL string) bool {
	u, err := url.Parse(databaseURL)
	if err != nil {
		return false
	}
	mode := u.Query().Get("sslmode")
	return mode == "verify-full" || mode == "verify-ca"
}

func corsMiddleware(next http.Handler, allowedOrigins []string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && slices.Contains(allowedOrigins, origin) {
			w.Header().Add("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// parseSessionTTL reads SESSION_TTL (Go duration, e.g. 24h). Empty → default.
func parseSessionTTL() time.Duration {
	raw := strings.TrimSpace(os.Getenv("SESSION_TTL"))
	if raw == "" {
		return 0
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		log.Printf("ignoring invalid SESSION_TTL %q: %v", raw, err)
		return 0
	}
	return d
}
