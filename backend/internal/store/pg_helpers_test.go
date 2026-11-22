package store

import (
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
)

func TestFormatDate_Time(t *testing.T) {
	tm := time.Date(2026, 9, 1, 15, 30, 45, 0, time.UTC)
	out := formatDate(tm)
	if out != "2026-09-01" {
		t.Fatalf("expected 2026-09-01, got %s", out)
	}
}

func TestPGPoolDefaults(t *testing.T) {
	t.Setenv("PGCONNECT_TIMEOUT", "")
	dsn := "postgres://test@sample-pooler.example.com/test?sslmode=verify-full"
	cfg, err := parsePGConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ConnectTimeout != 10*time.Second || cfg.DefaultQueryExecMode != pgx.QueryExecModeCacheStatement {
		t.Fatalf("connect timeout = %v; query mode = %v", cfg.ConnectTimeout, cfg.DefaultQueryExecMode)
	}
	if cfg.TLSConfig == nil || cfg.TLSConfig.InsecureSkipVerify || cfg.TLSConfig.ServerName != cfg.Host {
		t.Fatal("verify-full did not configure host verification")
	}
	if custom, err := parsePGConfig(dsn + "&connect_timeout=25"); err != nil || custom.ConnectTimeout != 25*time.Second {
		t.Fatalf("connect_timeout override not preserved: %v", err)
	}
	db := stdlib.OpenDB(*cfg) // sql.DB does not connect until first use.
	defer db.Close()
	configurePGPool(db)
	if db.Stats().MaxOpenConnections != 10 || pgMaxIdleConns != 2 || pgMaxIdleTime != time.Minute || pgMaxLifetime != 5*time.Minute {
		t.Fatal("unexpected PostgreSQL pool defaults")
	}
}
