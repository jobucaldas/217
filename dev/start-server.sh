#!/bin/bash
# Wait for PostgreSQL to be ready, then start the Go backend server
set -e

DB_URL="${DATABASE_URL:-postgres://app_217:app_217@localhost:5432/app_217?sslmode=disable}"

echo "Waiting for PostgreSQL at localhost:5432..."
for i in $(seq 1 30); do
  if pg_isready -h localhost -p 5432 -U app_217 -d app_217 2>/dev/null; then
    echo "PostgreSQL is ready!"
    break
  fi
  echo "attempt $i..."
  sleep 1
done

echo "Running migrations..."
cd /workspace/backend
go run ./cmd/server -db "$DB_URL" -migrate-only 2>&1 || echo "Migration warning"

echo ""
echo "================================================"
echo "  217 Backend Server starting on :3000"
echo "  Database: $DB_URL"
echo "================================================"
echo ""

exec go run ./cmd/server -addr ":3000" -db "$DB_URL"
