Project: 217

Cross-platform application for tracking anticonceptional intake.

## Overview
Android-first Flutter app for tracking anticonceptional intake via a calendar UI. Multi-user support with WorkOS AuthKit authentication, dark mode, and English, Português and Español UI (follows the device language; English otherwise).

Roles are picked once after first sign-in (`users.role` is NULL until then):
- **owner** — takes the pill; logs Taken/Missed, notes, intimacy and period days; creates the invite. Never joins another calendar.
- **partner** — joins one owner's calendar read-only via invite; gets optional PMS and pill-not-logged alerts (separate toggles + times).
Switching role is refused while a calendar is shared. Period days drive cycle/PMS predictions (`backend/internal/cycle`), drawn on both calendars (dashed amber ring = PMS, pink drop = period, outlined drop = predicted period).

## Tech Stack
- Client: Flutter (Android + web)
- Backend: Go — REST API
- Auth: WorkOS AuthKit (PKCE; API key server-side only)
- Database: PostgreSQL 16 — containerized via Podman
- Reverse Proxy: Caddy — Flutter web UI + `/api/*`

## Layout
- `backend/` — Go API (`Dockerfile`: `dev` stage + production image)
- `frontend/` — Flutter app (web, Android, Windows, Linux), `Dockerfile` (web bundle image), `Caddyfile` (local proxy)
- `docker-compose.yml` — local stack
- Deployment manifests live in a separate infra repo; this repo only publishes images and APKs.

## Development Environment
Fully containerized with Podman. DO NOT install project SDKs on the host. Go tooling runs in `localhost/217-dev` (the `dev` stage of `backend/Dockerfile`); Flutter tooling runs in `ghcr.io/cirruslabs/flutter:stable`.

```sh
make dev-up          # postgres + backend + caddy
make web      # Flutter web → frontend/build/web (served at :8787)
make test-backend    # gofmt/test/vet/build in container
make test-frontend     # flutter analyze + test in container
make apk      # debug APK in container
```

## Architecture
```
Browser (same origin) cookie flow:
 / → Flutter web → GET /api/auth/workos (JSON + binding cookie) → AuthKit → /api/auth/workos/callback → cookie → /

Android deep-link PKCE:
  Flutter → AuthKit → com.jobucaldas.a217://… → POST /api/auth/workos/exchange → Bearer
```

```
┌──────────────┐                 ┌─────────┐
│ Flutter web  │  cookie AuthKit │ WorkOS  │
│ or Android   │ ──────────────> │ AuthKit │
└──────┬───────┘                 └─────────┘
       │ /api/* (cookie or Bearer)
       v
┌──────────────┐   /api/*   ┌──────────┐   SQL   ┌────────────┐
│ Caddy :8787  │ ─────────> │ Go API   │ ──────> │ PostgreSQL │
└──────────────┘            └──────────┘         └────────────┘
```

## API Endpoints

### Auth
- `GET /api/auth/workos` — browser AuthKit start
- `GET /api/auth/workos/callback` — browser callback
- `POST /api/auth/workos/exchange` — native PKCE exchange
- `GET /api/auth/session` — cookie or Bearer
- `POST /api/auth/logout`

### Entries (auth required)
- `GET /api/entries?year=YYYY&month=MM`
- `GET|POST|DELETE /api/entries/{date}` — body `{taken, notes, heart, period}`
- `GET /api/stats?year=YYYY&month=MM`
- `GET /api/cycle?today=YYYY-MM-DD` — period starts + next predicted periods/PMS windows

### Roles, sharing, alerts (auth required)
- `PUT /api/account/role` — `{role: owner|partner}`; 409 while shared
- `POST /api/share/enable|revoke` (owner), `POST /api/share/accept` (unset role or partner)
- `GET|PUT /api/partner-alerts` (partner) — `{pms_enabled, pms_time, pill_enabled, pill_time}`

## Testing expectations
- Backend: `make test-backend`
- Mobile: `make test-frontend`
- Web tryout: `make web` then open http://localhost:8787/
- APK: `make apk`
- **UI quality (agent directive, not a testing preference):** never ship Flutter UI without dark **and** light coverage. CI must fail unreadable contrast and broken “today” CTA persistence (`frontend/test/theme_contrast_test.dart`, `frontend/test/today_nudge_test.dart`). **Not running those checks is unacceptable agent behavior** — same class as skipping the PR merge loop.

## Remaining gaps
- Live WorkOS sign-in / authenticated calendar not verified in CI
- Reminder delivery on native Android (previous Web Push/PWA path) not ported
- Partner alerts are local Android notifications planned from the last sync (app open/resume); no server push, so a pill logged after his last sync can still trigger that day's alert. Web shows the toggles but cannot deliver.
