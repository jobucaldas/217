package main

import (
	"flag"
	"log"
	"os"

	"217/backend/db"
	"217/backend/internal/server"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func main() {
	addr := flag.String("addr", ":8080", "server address")
	dbURL := flag.String("db", "", "postgres connection string (DATABASE_URL)")
	runMigrations := flag.Bool("migrate", true, "run database migrations on startup")
	migrateOnly := flag.Bool("migrate-only", false, "run migrations and exit")
	flag.Parse()

	dsn := *dbURL
	if dsn == "" {
		dsn = os.Getenv("DATABASE_URL")
	}

	if *runMigrations || *migrateOnly {
		if dsn == "" {
			if *migrateOnly {
				log.Fatal("DATABASE_URL or -db is required for migrations")
			}
		} else if err := db.RunMigrations(dsn); err != nil {
			log.Fatalf("migration failed: %v", err)
		}
	}

	if *migrateOnly {
		return
	}

	push := server.PushConfig{
		PublicKey:  os.Getenv("VAPID_PUBLIC_KEY"),
		PrivateKey: os.Getenv("VAPID_PRIVATE_KEY"),
		Subject:    os.Getenv("VAPID_SUBJECT"),
	}
	if _, err := server.ValidatePushConfig(push); err != nil {
		log.Fatalf("invalid Web Push configuration: %v", err)
	}
	google := server.GoogleConfig{
		ClientID:     os.Getenv("GOOGLE_CLIENT_ID"),
		ClientSecret: os.Getenv("GOOGLE_CLIENT_SECRET"),
		AppBaseURL:   os.Getenv("APP_BASE_URL"),
	}
	appBaseURL := google.AppBaseURL
	if appBaseURL == "" {
		appBaseURL = os.Getenv("APP_BASE_URL")
	}
	log.Fatal(server.StartWithPush(*addr, dsn, appBaseURL, push, google))
}
