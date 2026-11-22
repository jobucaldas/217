package main

import (
	"flag"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"217/backend/db"
	"217/backend/internal/auth"
	"217/backend/internal/fieldcrypt"
	"217/backend/internal/mailer"
	"217/backend/internal/server"
	"217/backend/internal/store"
	"217/backend/internal/tlsinit"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func main() {
	addr := flag.String("addr", ":8080", "server address")
	dbURL := flag.String("db", "", "postgres connection string (DATABASE_URL)")
	runMigrations := flag.Bool("migrate", true, "run database migrations on startup")
	migrateOnly := flag.Bool("migrate-only", false, "run migrations and exit")
	resetEmail := flag.String("reset-password", "", "reset an account password from stdin and exit")
	initTLS := flag.String("init-tls", "", "write internal TLS certificates to this directory and exit")
	postgresUID := flag.Int("postgres-uid", 70, "owner of the PostgreSQL key written by -init-tls (70 in postgres:*-alpine)")
	backendUID := flag.Int("backend-uid", 10001, "owner of the API key written by -init-tls (the backend image's uid)")
	postgresHosts := flag.String("postgres-hosts", "postgres,localhost", "host names in the PostgreSQL certificate")
	backendHosts := flag.String("backend-hosts", "backend,localhost", "host names in the API certificate")
	flag.Parse()

	if *initTLS != "" {
		issued, err := tlsinit.Ensure(*initTLS, []tlsinit.Service{
			{Name: "postgres", Hosts: splitList(*postgresHosts), UID: *postgresUID},
			{Name: "backend", Hosts: splitList(*backendHosts), UID: *backendUID},
		}, map[string]map[string]string{"postgres": {"pg_hba.conf": tlsinit.PGHBA}}, time.Now())
		if err != nil {
			log.Fatalf("internal TLS: %v", err)
		}
		if issued {
			log.Printf("internal TLS certificates written to %s", *initTLS)
		} else {
			log.Printf("internal TLS certificates in %s are current", *initTLS)
		}
		return
	}

	dsn := *dbURL
	if dsn == "" {
		dsn = os.Getenv("DATABASE_URL")
	}

	var keyring *fieldcrypt.Keyring
	if raw := os.Getenv("DATA_ENCRYPTION_KEY"); raw != "" {
		var err error
		keyring, err = fieldcrypt.FromStrings(raw, os.Getenv("DATA_ENCRYPTION_KEY_PREVIOUS"))
		if err != nil {
			log.Fatalf("invalid DATA_ENCRYPTION_KEY: %v", err)
		}
	} else if dsn != "" {
		log.Fatal("DATA_ENCRYPTION_KEY is required: personal data is encrypted before it is stored (generate one with: openssl rand -base64 32)")
	}

	if *runMigrations || *migrateOnly {
		if dsn == "" {
			if *migrateOnly {
				log.Fatal("DATABASE_URL or -db is required for migrations")
			}
		} else if err := db.RunMigrations(migrationDSN(dsn), store.MigrationSteps(keyring)); err != nil {
			log.Fatalf("migration failed: %v", err)
		}
	}
	if *migrateOnly {
		return
	}
	if *resetEmail != "" {
		if dsn == "" {
			log.Fatal("DATABASE_URL or -db is required to reset a password")
		}
		s, err := store.NewPGStore(dsn, keyring)
		if err != nil {
			log.Fatalf("opening database: %v", err)
		}
		if err := s.Prepare(); err != nil {
			log.Fatalf("preparing database: %v", err)
		}
		if err := resetPassword(s, *resetEmail, os.Stdin, os.Stdout); err != nil {
			log.Fatal(err)
		}
		return
	}

	log.Fatal(server.Run(server.Config{
		Addr:           *addr,
		DatabaseURL:    dsn,
		AppBaseURL:     os.Getenv("APP_BASE_URL"),
		AllowedOrigins: os.Getenv("APP_ALLOWED_ORIGINS"),
		Push: server.PushConfig{
			PublicKey:  os.Getenv("VAPID_PUBLIC_KEY"),
			PrivateKey: os.Getenv("VAPID_PRIVATE_KEY"),
			Subject:    os.Getenv("VAPID_SUBJECT"),
		},
		WorkOS: server.WorkOSConfig{
			APIKey:     os.Getenv("WORKOS_API_KEY"),
			ClientID:   os.Getenv("WORKOS_CLIENT_ID"),
			AppBaseURL: os.Getenv("APP_BASE_URL"),
		},
		OIDC:           &auth.OIDC{Issuer: os.Getenv("OIDC_ISSUER"), ClientID: os.Getenv("OIDC_CLIENT_ID"), ClientSecret: os.Getenv("OIDC_CLIENT_SECRET"), Name: os.Getenv("OIDC_NAME")},
		Keyring:        keyring,
		PrivacyContact: os.Getenv("PRIVACY_CONTACT"),
		TLSCertFile:    os.Getenv("TLS_CERT_FILE"),
		TLSKeyFile:     os.Getenv("TLS_KEY_FILE"),
		SMTP: mailer.Config{
			Host:     os.Getenv("SMTP_HOST"),
			Port:     os.Getenv("SMTP_PORT"),
			User:     os.Getenv("SMTP_USER"),
			Password: os.Getenv("SMTP_PASS"),
			From:     os.Getenv("SMTP_FROM"),
		},
		AuthPasswordEnabled: flagBool("AUTH_PASSWORD_ENABLED", true),
		AuthWorkOSEnabled:   flagBool("AUTH_WORKOS_ENABLED", true),
	}))
}

// migrationDSN prefers DATABASE_URL_UNPOOLED: migrations need a direct
// connection when DATABASE_URL goes through a transaction pooler.
func migrationDSN(dsn string) string {
	if direct := strings.TrimSpace(os.Getenv("DATABASE_URL_UNPOOLED")); direct != "" {
		return direct
	}
	return dsn
}

// flagBool parses a boolean environment variable; nil when unset or invalid.
func flagBool(name string, def bool) *bool {
	raw := os.Getenv(name)
	if raw == "" {
		return &def
	}
	v, err := strconv.ParseBool(raw)
	if err != nil {
		log.Printf("ignoring invalid %s=%q", name, raw)
		return &def
	}
	return &v
}

func splitList(s string) []string {
	var out []string
	for _, part := range strings.Split(s, ",") {
		if part = strings.TrimSpace(part); part != "" {
			out = append(out, part)
		}
	}
	return out
}
