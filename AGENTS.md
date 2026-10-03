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
- Database: PostgreSQL 16 — containerized (Docker Compose; Podman works too)
- Reverse Proxy: Caddy — Flutter web UI + `/api/*`

## Layout
- `backend/` — Go API (`Dockerfile`: `dev` stage + production image)
- `frontend/` — Flutter app (web, Android, Windows, Linux), `Dockerfile` (web image: `local` stage builds from source, `prebuilt` is what CI publishes), `Caddyfile` (serves the bundle, proxies `/api/*`)
- `docker-compose.yml` — dev stack + tooling (built from local code); end users run the compose file embedded in `README.md` against GHCR images
- Deployment manifests live in a separate infra repo; this repo only publishes images and APKs.

## Development Environment
Fully containerized with Docker Compose (Podman works too). DO NOT install project SDKs on the host. No Makefile: everything is a compose service (see the Development section of `README.md`).

```sh
docker compose up --build                 # postgres + backend + web (built from local code) at :8787
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
- Backend: `docker compose run --rm test-backend`
- Frontend: `docker compose run --rm test-frontend`
- Web tryout: `docker compose up --build` then open http://localhost:8787/
- APK: `docker compose run --rm apk`
- **UI quality (agent directive, not a testing preference):** never ship Flutter UI without dark **and** light coverage. CI must fail unreadable contrast and broken “today” CTA persistence (`frontend/test/theme_contrast_test.dart`, `frontend/test/today_nudge_test.dart`). **Not running those checks is unacceptable agent behavior** — same class as skipping the PR merge loop.

## Remaining gaps
- Live WorkOS sign-in / authenticated calendar not verified in CI
- Reminder delivery on native Android (previous Web Push/PWA path) not ported
- Partner alerts are local Android notifications planned from the last sync (app open/resume); no server push, so a pill logged after his last sync can still trigger that day's alert. Web shows the toggles but cannot deliver.
