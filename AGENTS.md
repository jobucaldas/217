Project: 217

Cross-platform application for tracking anticonceptional intake.

## Overview
Android-first Flutter app for tracking anticonceptional intake via a calendar UI. Multi-user support with WorkOS AuthKit authentication, dark mode, and English, Português and Español UI (follows the device language; English otherwise).

## Tech Stack
- Client: Flutter (Android + web)
- Backend: Go — REST API
- Auth: WorkOS AuthKit (PKCE; API key server-side only)
- Database: PostgreSQL 16 — containerized via Podman
- Reverse Proxy: Caddy — Flutter web UI + `/api/*`

## Development Environment
Fully containerized with Podman. DO NOT install project SDKs on the host. Go tooling runs in `localhost/217-dev`; Flutter tooling runs in `ghcr.io/cirruslabs/flutter:stable`.

```sh
make dev-up          # postgres + backend + caddy
make mobile-web      # Flutter web → mobile/build/web (served at :8787)
make test-backend    # gofmt/test/vet/build in container
make test-mobile     # flutter analyze + test in container
make mobile-apk      # debug APK in container
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
- `GET|POST|DELETE /api/entries/{date}`
- `GET /api/stats?year=YYYY&month=MM`

## Testing expectations
- Backend: `make test-backend`
- Mobile: `make test-mobile`
- Web tryout: `make mobile-web` then open http://localhost:8787/
- APK: `make mobile-apk`
- **UI quality (agent directive, not a testing preference):** never ship Flutter UI without dark **and** light coverage. CI must fail unreadable contrast and broken “today” CTA persistence (`mobile/test/theme_contrast_test.dart`, `mobile/test/today_nudge_test.dart`). **Not running those checks is unacceptable agent behavior** — same class as skipping the PR merge loop.

## Remaining gaps
- Live WorkOS sign-in / authenticated calendar not verified in CI
- Reminder delivery on native Android (previous Web Push/PWA path) not ported
