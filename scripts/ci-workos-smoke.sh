#!/usr/bin/env bash
# Deploy smoke: boot the API against Postgres with real WORKOS_*
# secrets and prove AuthKit is wired (config + continue URL + password off).
set -euo pipefail

: "${WORKOS_CLIENT_ID:?WORKOS_CLIENT_ID must be set (repo Actions secret)}"
: "${WORKOS_API_KEY:?WORKOS_API_KEY must be set (repo Actions secret)}"
: "${DATABASE_URL:?DATABASE_URL must be set}"
: "${APP_BASE_URL:=http://localhost:8787}"
: "${BACKEND_ADDR:=127.0.0.1:3000}"
: "${BASE_URL:=http://${BACKEND_ADDR}}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/backend"

echo "Building API…"
go build -mod=readonly -o /tmp/217-server ./cmd/server

echo "Starting API on ${BACKEND_ADDR}…"
APP_BASE_URL="${APP_BASE_URL}" \
  WORKOS_CLIENT_ID="${WORKOS_CLIENT_ID}" \
  WORKOS_API_KEY="${WORKOS_API_KEY}" \
  DATABASE_URL="${DATABASE_URL}" \
  /tmp/217-server -addr "${BACKEND_ADDR}" -db "${DATABASE_URL}" &
PID=$!
cleanup() { kill "${PID}" 2>/dev/null || true; wait "${PID}" 2>/dev/null || true; }
trap cleanup EXIT

echo "Waiting for healthz…"
for i in $(seq 1 60); do
  if curl -fsS "${BASE_URL}/healthz" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "${PID}" 2>/dev/null; then
    echo "server exited early" >&2
    exit 1
  fi
  sleep 1
  if [[ "${i}" -eq 60 ]]; then
    echo "healthz timeout" >&2
    exit 1
  fi
done

curl -fsS "${BASE_URL}/readyz" >/dev/null

echo "GET /api/auth/config…"
cfg="$(curl -fsS "${BASE_URL}/api/auth/config")"
echo "${cfg}" | python3 -c '
import json,sys
b=json.load(sys.stdin)
assert b.get("authkit") is True, b
assert b.get("password") is False, b
assert str(b.get("workos_client_id", "")).startswith("client_"), "workos_client_id missing"
print("authkit=true password=false workos_client_id=present")
'

echo "GET /api/auth/workos (JSON auth_url + binding cookie)…"
body="$(curl -fsS -c /tmp/217-cookies.txt -H 'Accept: application/json' "${BASE_URL}/api/auth/workos")"
echo "${body}" | python3 -c "
import json,os,sys,re
b=json.load(sys.stdin)
u=b.get('auth_url') or ''
assert 'workos.com' in u or 'authkit' in u.lower(), b
assert os.environ['WORKOS_CLIENT_ID'] in u, b
print('auth_url ok')
"
# Binding cookie must be set for the callback path.
grep -qi '217_oauth_binding' /tmp/217-cookies.txt

echo "POST /api/auth/login → 403…"
code="$(curl -sS -o /tmp/217-login.json -w '%{http_code}' \
  -X POST "${BASE_URL}/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"email":"ci@example.com","password":"nope"}')"
test "${code}" = "403"

echo "GET /api/auth/session (anonymous)…"
sess="$(curl -fsS "${BASE_URL}/api/auth/session")"
echo "${sess}" | python3 -c '
import json,sys
b=json.load(sys.stdin)
assert b.get("user") is None, b
print("anonymous session ok")
'

echo "WorkOS deploy smoke passed."
