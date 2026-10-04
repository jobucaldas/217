package db

import (
	"database/sql"
	"fmt"
	"log"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func RunMigrations(databaseURL string, steps map[string]Step) error {
	if databaseURL == "" {
		return fmt.Errorf("no database URL provided")
	}

	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return fmt.Errorf("opening database for migration: %w", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		return fmt.Errorf("pinging migration database: %w", err)
	}

	log.Println("running database migrations...")
	if err := Migrate(db, steps); err != nil {
		return fmt.Errorf("migration failed: %w", err)
	}
	log.Println("migrations complete")
	return nil
}
