# 217

Private bilingual (Português/English) anticonceptional intake tracker.

- **Client:** Flutter (web + Android)
- **API:** Go + PostgreSQL
- **Auth:** WorkOS AuthKit (PKCE; API key server-side only)

## Requirements

Podman and podman-compose on the host. Go and Flutter run in containers — do not install project SDKs on the host.

## Start locally

Copy `.env.example` to ignored `.env.local`. Set `WORKOS_API_KEY` from the WorkOS Dashboard (server-only). `WORKOS_CLIENT_ID` is public. Register redirect URIs:

- `http://localhost:8787/api/auth/workos/callback` (browser)
- `com.jobucaldas.a217://auth/callback` (Android)

```sh
make dev-up       # postgres + Go API + Caddy
make mobile-web   # Flutter web → mobile/build/web
```

Open <http://localhost:8787/>. Stop with `make dev-down`.

Host port defaults to **8787** (`HTTP_PORT` / matching `APP_BASE_URL` to override).

## Android

```sh
make test-mobile
make mobile-apk
```

Install `mobile/build/app/outputs/flutter-apk/app-debug.apk`. Emulator API base defaults to `http://10.0.2.2:8787` (`--dart-define=API_BASE_URL=...` to override at build time, or **Settings → Advanced options → Self-hosted server URL** in the app).

Every push to `main` (after CI is green) publishes APK + GHCR with the same dual names:
- **nightly** — rolling GitHub Release (`217-nightly.apk`) and GHCR tags `:nightly` / `:dev`
- **datetime_sha** — immutable GitHub Release `YYYYMMDDHHMMSS_<shortsha>` (`217-<tag>.apk`) and matching GHCR tags

## Layout

| Path | Role |
|---|---|
| `mobile/` | Flutter client |
| `backend/` | Go API |
| `frontend/` | Caddy image that serves the Flutter web bundle |
| `deploy/` | kustomize / home-lab manifests |
| `dev/Containerfile` | Go toolchain image used by `make test-backend` |
| `scripts/` | CI helpers |

## Validate

```sh
make test-backend
make test-mobile
make mobile-web
```

## Security

- Never commit `WORKOS_API_KEY` or other secrets
- Flutter receives only `WORKOS_CLIENT_ID` (public)
- Session tokens are stored as SHA-256 digests in PostgreSQL
