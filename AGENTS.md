Project: 217

Cross-platform application for tracking anticonceptional intake.

## Overview
Android-first Flutter app for tracking anticonceptional intake via a calendar UI. Multi-user support with WorkOS AuthKit authentication, dark mode, and bilingual (Pt/En) UI.

## Tech Stack
- Mobile: Flutter (Android first)
- Backend: Go — REST API
- Auth: WorkOS AuthKit (PKCE; API key server-side only)
- Database: PostgreSQL 16 — containerized via Podman
- Reverse Proxy: Caddy — proxies `/api/*`

## Development Environment
Fully containerized with Podman. DO NOT install project SDKs on the host. Go tooling runs in `localhost/217-dev`; Flutter tooling runs in `ghcr.io/cirruslabs/flutter:stable`.

```sh
make dev-up          # postgres + backend + caddy
make test-backend    # gofmt/test/vet/build in container
make test-mobile     # flutter analyze + test in container
make mobile-apk      # debug APK in container
```

## Architecture
```
┌──────────────┐   AuthKit+PKCE   ┌─────────┐
│ Flutter app  │ ───────────────> │ WorkOS  │
│ (Android)    │ <── code ─────── │ AuthKit │
└──────┬───────┘                  └─────────┘
       │ POST /api/auth/workos/exchange
       │ Bearer session
       v
┌──────────────┐   /api/*   ┌──────────┐   SQL   ┌────────────┐
│ Caddy :8080  │ ─────────> │ Go API   │ ──────> │ PostgreSQL │
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
- `GET|POST /api/entries/{date}`
- `GET /api/stats?year=YYYY&month=MM`

## Testing expectations
- Backend: `make test-backend`
- Mobile: `make test-mobile`
- APK: `make mobile-apk`

## Remaining gaps
- Live WorkOS sign-in / authenticated calendar not verified in CI
- Reminder delivery on native Android (previous Web Push/PWA path) not ported
