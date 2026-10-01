#!/bin/bash
set -e

echo "=== Prefer make targets ==="
echo "  make dev-up       # postgres + Go API + Caddy"
echo "  make mobile-web   # Flutter web → mobile/build/web"
echo "  open http://localhost:8787/"
echo ""
echo "Legacy one-shot backend only (no Flutter):"
cd "$(dirname "$0")/backend"
go run ./cmd/server &
BACKEND_PID=$!
echo "Backend on http://localhost:8080 (PID: $BACKEND_PID)"

cleanup() {
  echo "Shutting down..."
  kill $BACKEND_PID 2>/dev/null
  exit 0
}
trap cleanup SIGINT SIGTERM
wait $BACKEND_PID
