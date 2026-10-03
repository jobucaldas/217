package server

import (
	"encoding/base64"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"217/backend/internal/auth"
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

func Start(addr, databaseURL string) error {
	return StartWithPush(addr, databaseURL, "", PushConfig{})
}

func StartWithPush(addr, databaseURL, appBaseURL string, push PushConfig, workosConfigs ...WorkOSConfig) error {
	canonicalBaseURL, err := auth.ValidateAppBaseURL(appBaseURL)
	if err != nil {
		return err
	}
	appBaseURL = canonicalBaseURL
	if len(workosConfigs) > 0 && workosConfigs[0].AppBaseURL != "" {
		workosBaseURL, validateErr := auth.ValidateAppBaseURL(workosConfigs[0].AppBaseURL)
		if validateErr != nil {
			return validateErr
		}
		if appBaseURL != "" && appBaseURL != workosBaseURL {
			return fmt.Errorf("APP_BASE_URL must be consistent across server and WorkOS OAuth configuration")
		}
		appBaseURL = workosBaseURL
		workosConfigs[0].AppBaseURL = workosBaseURL
	}
	validatedPush, err := ValidatePushConfig(push)
	if err != nil {
		return err
	}
	push = validatedPush
	var s store.Store

	if databaseURL != "" {
		log.Println("connecting to postgres")
		s, err = store.NewPGStore(databaseURL)
		if err != nil {
			return fmt.Errorf("connect to database: %w", err)
		}
		log.Println("connected to postgres")
	} else {
		log.Println("using in-memory store")
		s = store.NewMemoryStore()
	}
	defer s.Close()

	h := handler.NewWithVAPID(s, push.PublicKey)
	h.SetAppBaseURL(appBaseURL)
	if ttl := parseSessionTTL(); ttl > 0 {
		h.SetSessionDuration(ttl)
	}

	if len(workosConfigs) > 0 {
		cfg := workosConfigs[0]
		if cfg.ClientID != "" && cfg.AppBaseURL != "" {
			provider, providerErr := auth.NewWorkOSOAuth(cfg.APIKey, cfg.ClientID, cfg.AppBaseURL)
			if providerErr != nil {
				log.Printf("workos oauth disabled: %v", providerErr)
			} else {
				h.SetOAuthProvider(provider)
				if cfg.APIKey == "" {
					log.Println("workos oauth enabled (PKCE public exchange)")
				} else {
					log.Println("workos oauth enabled (PKCE public exchange; API key is not sent on code exchange)")
				}
			}
		} else {
			log.Println("workos oauth disabled: missing WORKOS_CLIENT_ID or APP_BASE_URL")
		}
	} else {
		log.Println("workos oauth disabled: missing configuration")
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

	mux.HandleFunc("GET /api/entries", h.AuthMiddleware(h.ListEntries))
	mux.HandleFunc("GET /api/entries/{date}", h.AuthMiddleware(h.GetEntry))
	mux.HandleFunc("POST /api/entries/{date}", h.AuthMiddleware(h.UpsertEntry))
	mux.HandleFunc("DELETE /api/entries/{date}", h.AuthMiddleware(h.DeleteEntry))
	mux.HandleFunc("GET /api/stats", h.AuthMiddleware(h.GetStats))

	mux.HandleFunc("DELETE /api/account", h.AuthMiddleware(h.DeleteAccount))
	mux.HandleFunc("PUT /api/account/role", h.AuthMiddleware(h.SetRole))
	mux.HandleFunc("GET /api/cycle", h.AuthMiddleware(h.GetCycle))
	mux.HandleFunc("GET /api/partner-alerts", h.AuthMiddleware(h.GetPartnerAlerts))
	mux.HandleFunc("PUT /api/partner-alerts", h.AuthMiddleware(h.UpsertPartnerAlerts))
	mux.HandleFunc("GET /api/share", h.AuthMiddleware(h.GetShare))
	mux.HandleFunc("POST /api/share/enable", h.AuthMiddleware(h.EnableShare))
	mux.HandleFunc("POST /api/share/revoke", h.AuthMiddleware(h.RevokeShare))
	mux.HandleFunc("POST /api/share/accept", h.AuthMiddleware(h.AcceptShare))
	mux.HandleFunc("GET /api/inbox", h.AuthMiddleware(h.ListInbox))
	mux.HandleFunc("POST /api/inbox/{id}/read", h.AuthMiddleware(h.MarkInboxNoteRead))
	mux.HandleFunc("POST /api/partner-notes", h.AuthMiddleware(h.CreatePartnerNote))

	mux.HandleFunc("GET /api/reminders/preferences", h.AuthMiddleware(h.GetReminderPreference))
	mux.HandleFunc("PUT /api/reminders/preferences", h.AuthMiddleware(h.UpsertReminderPreference))
	mux.HandleFunc("GET /api/reminders/vapid-public-key", h.AuthMiddleware(h.VAPIDPublicKey))
	mux.HandleFunc("POST /api/reminders/subscriptions", h.AuthMiddleware(h.SavePushSubscription))
	mux.HandleFunc("DELETE /api/reminders/subscriptions", h.AuthMiddleware(h.DeletePushSubscription))

	handlerWithCORS := corsMiddleware(mux, appBaseURL)

	log.Printf("server starting on %s", addr)
	return http.ListenAndServe(addr, handlerWithCORS)
}

func corsMiddleware(next http.Handler, appBaseURL string) http.Handler {
	allowedOrigin := originFromBaseURL(appBaseURL)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && allowedOrigin != "" && origin == allowedOrigin {
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

func originFromBaseURL(appBaseURL string) string {
	u, err := url.Parse(appBaseURL)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return ""
	}
	return u.Scheme + "://" + u.Host
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
