package store

import (
	"217/backend/db"
	"217/backend/internal/fieldcrypt"
)

// MigrateForTest applies the schema migrations to s's database (test
// helper). It lives here rather than in a _test.go file so handler tests
// can bring a raw PGStore up to the current schema the same way the store
// tests do.
func MigrateForTest(s *PGStore, kr *fieldcrypt.Keyring) error {
	return db.Migrate(s.db, MigrationSteps(kr))
}
