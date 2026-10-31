Project: 217

Cross-platform application for tracking anticonceptional intake.

## Overview
Android-first Flutter app for tracking anticonceptional intake via a calendar UI. Multi-user support with WorkOS AuthKit authentication, dark mode, and English, Português and Español UI (follows the device language; English otherwise).

Roles are picked once after first sign-in (`users.role` is NULL until then):
- **owner** — takes the pill; logs Taken/Missed, notes, intimacy and period days; creates the invite. Never joins another calendar.
- **partner** — joins one owner's calendar read-only via invite; gets optional PMS and pill-not-logged alerts (separate toggles + times).
Switching role is refused while a calendar is shared. Period days drive cycle/PMS predictions (`backend/internal/cycle`), drawn on both calendars (dashed amber ring = expected PMS, the 7 days before a predicted period; pink drop = period, outlined drop = predicted period).
Owners can record cycling, perimenopause, or menopause; menopause suppresses PMS, while perimenopause keeps PMS when period days are logged.
Linked owner and partner can message each other (Messages screen, unread badge on the calendar app bar); bodies are sealed in `partner_notes` (`sender` = owner|partner).

## Tech Stack
- Client: Flutter (Android + web)
- Backend: Go — REST API
- Auth: WorkOS AuthKit (PKCE; API key server-side only)
- Database: PostgreSQL 16 — containerized (Docker Compose; Podman works too)
- Reverse Proxy: Caddy — Flutter web UI + `/api/*`
- Crypto: personal data sealed in the API (`backend/internal/fieldcrypt`, AES-256-GCM, `DATA_ENCRYPTION_KEY`) before PostgreSQL; internal hops TLS via the `certs` service (`server -init-tls`)

## Layout
- `backend/` — Go API (`Dockerfile`: `dev` stage + production image)
- `frontend/` — Flutter app (web, Android, Windows, Linux), `Dockerfile` (web image: `local` stage builds from source, `prebuilt` is what CI publishes), `Caddyfile` (serves the bundle, proxies `/api/*`)
- `docker-compose.yml` — dev stack + tooling (built from local code); end users run the compose file embedded in `README.md` against GHCR images
- Deployment manifests live in a separate infra repo; this repo only publishes images and APKs.

## Development Environment
Fully containerized with Docker Compose (Podman works too). DO NOT install project SDKs on the host. No Makefile: everything is a compose service (see the Development section of `README.md`).

```sh
docker compose up --build                 # certs + postgres + backend + web (built from local code) at :8787
docker compose run --rm test-backend      # gofmt/vet/test
docker compose run --rm test-frontend     # flutter analyze + test
docker compose run --rm apk               # debug APK
```

Docs stay infrastructure-agnostic: users get the README compose file (GHCR images, no clone); developers use `docker-compose.yml` with local code.

## Architecture
```
Browser (same origin) cookie flow:
 / → Flutter web → GET /api/auth/workos (JSON + binding cookie) → AuthKit → /api/auth/workos/callback → cookie → /

Android deep-link PKCE:
  Flutter → AuthKit → com.caldasstudios.app217://… → POST /api/auth/workos/exchange (+ Keystore public key) → Bearer
Android renewal (no sign-in): POST /api/auth/device/challenge → Keystore signs → POST /api/auth/device/session → Bearer
```

Offline-first client: `ApiClient` keeps the last session, months, cycle and alert prefs per account in `LocalStore` (`frontend/lib/src/offline/`: SQLCipher SQLite on Android, memory elsewhere) and queues day edits in its outbox, sent in order by `syncPending()` (edit, resume, first request back online). Sign-out/account switch/server change clear it.

```
┌──────────────┐                 ┌─────────┐
│ Flutter web  │  cookie AuthKit │ WorkOS  │
│ or Android   │ ──────────────> │ AuthKit │
└──────┬───────┘                 └─────────┘
       │ /api/* (cookie or Bearer)
       v
┌──────────────┐ /api/* TLS ┌──────────┐ SQL TLS ┌────────────┐
│ Caddy :8787  │ ─────────> │ Go API   │ ──────> │ PostgreSQL │
└──────────────┘            └──────────┘ sealed  └────────────┘
```

## API Endpoints

### Auth
- `GET /api/auth/workos` — browser AuthKit start
- `GET /api/auth/workos/callback` — browser callback; the redirect URI is chosen at login from the request host (`X-Forwarded-Host`/`Host`) if it is in `APP_BASE_URL` + `APP_ALLOWED_ORIGINS`, else `APP_BASE_URL`, and stored with the attempt (sealed) for the exchange and final redirect
- `POST /api/auth/workos/exchange` — native PKCE exchange; optional `device_public_key` (base64 PKIX P-256) → `device_key_id`
- `POST /api/auth/device/challenge` — `{key_id}` → single-use `{challenge}` (2 min)
- `POST /api/auth/device/session` — `{key_id, challenge, signature}` (SHA256withECDSA over `217 device session v1\n<key_id>\n<challenge>`) → Bearer; logout revokes the key
- `GET /api/auth/session` — cookie or Bearer
- `POST /api/auth/logout`

### Entries (auth required)
- `GET /api/entries?year=YYYY&month=MM`
- `GET|POST|DELETE /api/entries/{date}` — body `{taken, notes, heart, period}`
- `GET /api/stats?year=YYYY&month=MM`
- `GET /api/cycle?today=YYYY-MM-DD` — period starts + next predicted periods/PMS windows

### Reminders (auth required)
- `GET|PUT /api/reminders/preferences` — `{enabled, time, timezone, repeat_enabled, repeat_minutes}`; `repeat_minutes` is 1-120 and repeats the owner's own "pill not logged" reminder until logged or day end

### Privacy (auth required; reachable before consent)
- `PUT /api/account/consent` — `{version}`; every other data endpoint answers 403 `consent required` until the current `model.ConsentVersion` is agreed
- `GET /api/account/export` — all data about the caller (JSON attachment)
- `DELETE /api/account` — erasure (WorkOS identity too when `WORKOS_API_KEY` is set)

### Roles, sharing, alerts (auth required)
- `PUT /api/account/role` — `{role: owner|partner}`; 409 while shared
- `PUT /api/account/stage` — `{stage: cycling|perimenopause|menopause}` (owner only)
- `POST /api/share/enable|revoke` (owner), `POST /api/share/accept` (unset role or partner)
- `GET|PUT /api/partner-alerts` (partner) — `{pms_enabled, pms_time, pill_enabled, pill_time, pill_repeat_enabled, pill_repeat_minutes}`; `pill_repeat_minutes` is 1-120

### Messages (auth required; owner ↔ linked partner)
- `GET /api/inbox` — `{notes: [{id, sender, body, created_at, read_at, from_name, from_email, from_me}]}`, sent and received, newest first; `unread_notes` in the session share counts unread received ones
- `POST /api/messages` — `{body}` (≤ 2000 bytes) to the other side of the active share; 403 `share inactive` or when the recipient has not agreed to the current notice (`POST /api/partner-notes` is kept as an alias for older apps)
- `POST /api/inbox/{id}/read` — recipient only

## Testing expectations
- Backend: `docker compose run --rm test-backend` (store tests also hit PostgreSQL when `TEST_DATABASE_URL` is set; CI sets it)
- New personal-data columns are sealed (`internal/store/sealed.go`); `TestSealExistingRowsDropsPlaintext` checks a dump and the raw table files for plaintext
- Frontend: `docker compose run --rm test-frontend`
- Web tryout: `docker compose up --build` then open http://localhost:8787/
- APK: `docker compose run --rm apk`

## Remaining gaps
- Offline: cycle predictions are the last ones the server sent (no on-device recomputation); share, role, consent and alert settings need the server; desktop/web keep the offline copy in memory only and sign in again when the session ends
- Accounts signed in before device keys must sign in once more to get one
- Live WorkOS sign-in / authenticated calendar not verified in CI
- Reminder delivery on native Android (previous Web Push/PWA path) not ported
- Partner alerts are local Android notifications planned from the last sync (app open/resume); no server push, so a pill logged after his last sync can still trigger that day's alert. Web shows the toggles but cannot deliver.
- Message notifications are local too: the app checks `/api/inbox` on open/resume and every 2 minutes in the foreground (Settings toggle, Android only), so a message sent while the app is closed is announced the next time it opens.
