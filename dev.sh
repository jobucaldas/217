#!/bin/bash
# Start 217 development environment using podman-compose
# No host installations required beyond podman & podman-compose
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

case "${1:-help}" in
  up)
    echo "Starting all services..."
    podman-compose up -d
    echo ""
    echo "==========================================="
    echo "  217 is running!"
    echo ""
    echo "  Frontend: http://localhost:8080"
    echo "  API:      http://localhost:8080/api"
    echo "  DB:       localhost:5432"
    echo "==========================================="
    ;;
  down)
    podman-compose down
    echo "Services stopped."
    ;;
  rebuild)
    echo "Rebuilding frontend..."
    cd frontend && ./build.sh && cd ..
    echo "Restarting Caddy to pick up changes..."
    podman-compose restart caddy
    echo "Done. Refresh http://localhost:8080"
    ;;
  logs)
    podman-compose logs -f "${2:-caddy}"
    ;;
  psql)
    podman-compose exec postgres psql -U app_217 -d app_217
    ;;
  test)
    cd backend && go test ./... -v
    ;;
  help|*)
    echo "Usage: $0 {up|down|rebuild|logs|psql|test}"
    echo ""
    echo "  up       Start PostgreSQL + backend + Caddy"
    echo "  down     Stop all services"
    echo "  rebuild  Rebuild frontend WASM and restart Caddy"
    echo "  logs     View container logs (default: caddy)"
    echo "  psql     Open PostgreSQL shell"
    echo "  test     Run backend tests"
    ;;
esac
