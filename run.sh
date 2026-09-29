#!/bin/bash
set -e

echo "=== Starting 217 Backend ==="
cd "$(dirname "$0")/backend"
go run ./cmd/server &
BACKEND_PID=$!
echo "Backend running on http://localhost:8080 (PID: $BACKEND_PID)"

cleanup() {
  echo "Shutting down..."
  kill $BACKEND_PID 2>/dev/null
  exit 0
}
trap cleanup SIGINT SIGTERM

# For frontend (desktop mode), uncomment:
# cd "$(dirname "$0")/frontend"
# cargo run --features desktop

echo ""
echo "Frontend requires Dioxus CLI or wasm-bindgen to serve."
echo "Run: cd frontend && dx serve"
echo ""
echo "Press Ctrl+C to stop the backend."
wait $BACKEND_PID
