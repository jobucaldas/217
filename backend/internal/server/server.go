package server

import (
	"encoding/base64"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strings"

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

type GoogleConfig struct {
	ClientID     string
	ClientSecret string
	AppBaseURL   string
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

func StartWithPush(addr, databaseURL, appBaseURL string, push PushConfig, googleConfigs ...GoogleConfig) error {
	canonicalBaseURL, err := auth.ValidateAppBaseURL(appBaseURL)
	if err != nil {
		return err
	}
	appBaseURL = canonicalBaseURL
	if len(googleConfigs) > 0 && googleConfigs[0].AppBaseURL != "" {
		googleBaseURL, validateErr := auth.ValidateAppBaseURL(googleConfigs[0].AppBaseURL)
		if validateErr != nil {
			return validateErr
		}
		if appBaseURL != "" && appBaseURL != googleBaseURL {
			return fmt.Errorf("APP_BASE_URL must be consistent across server and Google OAuth configuration")
		}
		appBaseURL = googleBaseURL
		googleConfigs[0].AppBaseURL = googleBaseURL
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

	if len(googleConfigs) > 0 {
		google := googleConfigs[0]
		if google.ClientID != "" && google.ClientSecret != "" && google.AppBaseURL != "" {
			provider, providerErr := auth.NewGoogleOAuth(google.ClientID, google.ClientSecret, google.AppBaseURL)
			if providerErr != nil {
				log.Printf("google oauth disabled: %v", providerErr)
			} else {
				h.SetOAuthProvider(provider)
				log.Println("google oauth enabled")
			}
		} else {
			log.Println("google oauth disabled: missing GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, or APP_BASE_URL")
		}
	} else {
		log.Println("google oauth disabled: missing configuration")
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

	mux.HandleFunc("GET /api/auth/session", h.CurrentSession)
	mux.HandleFunc("POST /api/auth/logout", h.Logout)
	mux.HandleFunc("GET /api/auth/google", h.StartGoogleOAuth)
	mux.HandleFunc("GET /api/auth/google/callback", h.GoogleOAuthCallback)

	mux.HandleFunc("GET /api/entries", h.AuthMiddleware(h.ListEntries))
	mux.HandleFunc("GET /api/entries/{date}", h.AuthMiddleware(h.GetEntry))
	mux.HandleFunc("POST /api/entries/{date}", h.AuthMiddleware(h.UpsertEntry))
	mux.HandleFunc("GET /api/stats", h.AuthMiddleware(h.GetStats))

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
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		}

		if r.Method == http.MethodOptions {
			if origin != "" && allowedOrigin != "" && origin != allowedOrigin {
				http.Error(w, "forbidden", http.StatusForbidden)
				return
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func originFromBaseURL(baseURL string) string {
	u, err := url.Parse(baseURL)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return ""
	}
	return u.Scheme + "://" + u.Host
}
