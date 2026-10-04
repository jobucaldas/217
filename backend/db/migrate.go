package db

import (
	"database/sql"
	"embed"
	"fmt"
	"log"
	"sort"
	"strings"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

// Step is a migration written in Go, for changes SQL cannot make on its own
// (sealing existing rows needs the application's encryption key). Tx runs in
// the migration's transaction; NoTx runs outside one, for statements such as
// VACUUM, and must be safe to repeat if interrupted.
type Step struct {
	Tx   func(tx *sql.Tx) error
	NoTx func(db *sql.DB) error
}

// goSteps are the Go-coded migrations, ordered with the SQL files by name.
// Callers supply their implementations to Migrate.
var goSteps = []string{"018_seal_existing_rows", "019_rewrite_sealed_tables"}

// Migrate applies every pending migration in name order.
func Migrate(db *sql.DB, steps map[string]Step) error {
	return MigrateBefore(db, steps, "")
}

// MigrateBefore applies pending migrations whose name sorts before stop
// (every migration when stop is empty). Tests use it to seed an older schema.
func MigrateBefore(db *sql.DB, steps map[string]Step, stop string) error {
	files, err := migrationsFS.ReadDir("migrations")
	if err != nil {
		return fmt.Errorf("reading migrations dir: %w", err)
	}

	names := append([]string{}, goSteps...)
	for _, f := range files {
		if !f.IsDir() && strings.HasSuffix(f.Name(), ".sql") {
			names = append(names, f.Name())
		}
	}
	sort.Strings(names)

	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
		version VARCHAR(255) PRIMARY KEY,
		applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	)`); err != nil {
		return fmt.Errorf("creating schema migrations table: %w", err)
	}

	for _, name := range names {
		if stop != "" && name >= stop {
			break
		}
		var count int
		err := db.QueryRow("SELECT COUNT(*) FROM schema_migrations WHERE version = $1", name).Scan(&count)
		if err != nil {
			return fmt.Errorf("checking migration %s: %w", name, err)
		}
		if count > 0 {
			continue
		}

		var step Step
		if strings.HasSuffix(name, ".sql") {
			content, err := migrationsFS.ReadFile("migrations/" + name)
			if err != nil {
				return fmt.Errorf("reading %s: %w", name, err)
			}
			step.Tx = func(tx *sql.Tx) error {
				_, err := tx.Exec(string(content))
				return err
			}
		} else if step = steps[name]; step.Tx == nil && step.NoTx == nil {
			return fmt.Errorf("migration %s needs the data encryption key", name)
		}

		log.Printf("applying migration: %s", name)
		if step.NoTx != nil {
			if err := step.NoTx(db); err != nil {
				return fmt.Errorf("applying %s: %w", name, err)
			}
		}
		if step.Tx == nil {
			step.Tx = func(*sql.Tx) error { return nil }
		}
		tx, err := db.Begin()
		if err != nil {
			return fmt.Errorf("beginning %s: %w", name, err)
		}
		if err = step.Tx(tx); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("applying %s: %w", name, err)
		}
		if _, err = tx.Exec("INSERT INTO schema_migrations (version) VALUES ($1)", name); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("recording %s: %w", name, err)
		}
		if err = tx.Commit(); err != nil {
			return fmt.Errorf("committing %s: %w", name, err)
		}
	}

	return nil
}
