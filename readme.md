# 217

Private bilingual (Português/English) anticonceptional intake tracker.

**Flutter** client (web + Android) + **Go** API + PostgreSQL, authenticated with **WorkOS AuthKit** (PKCE). Browser sessions use `HttpOnly` cookies; Android uses bearer tokens.

## Requirements

Podman and podman-compose on the host. Go and Flutter tooling run in containers — do not install project SDKs on the host.

## Local development

Copy `.env.example` to ignored `.env.local`. Set `WORKOS_API_KEY` from the WorkOS Dashboard (server-only). `WORKOS_CLIENT_ID` is public. Register redirect URIs:

- `http://localhost:8787/api/auth/workos/callback` (browser)
- `com.jobucaldas.a217://auth/callback` (Android)

```sh
make dev-up       # postgres + Go API + Caddy (:8787)
make mobile-web   # Flutter web → mobile/build/web
```

Open <http://localhost:8787/>. Stop with `make dev-down`. Override host port with `HTTP_PORT=…` and matching `APP_BASE_URL`.

## Android

```sh
make test-mobile
make mobile-apk
```

Install `mobile/build/app/outputs/flutter-apk/app-debug.apk`. Emulator API base defaults to `http://10.0.2.2:8787` (`--dart-define=API_BASE_URL=...`).

## Tests

```sh
make test-backend
make test-mobile
```

## Home-lab deploy

Kustomize overlays live under `deploy/kustomize/`. Build images after `make mobile-web`:

```sh
podman build -t ghcr.io/jobucaldas/app-217-backend:dev -f backend/Dockerfile.prod backend
podman build -t ghcr.io/jobucaldas/app-217-frontend:dev -f frontend/Dockerfile.prod .
kubectl --context home-lab apply -k deploy/kustomize/overlays/dev
```

See `deploy/kustomize/overlays/dev/README.md`.

## Security

- Never commit `WORKOS_API_KEY`
- Flutter receives only public `WORKOS_CLIENT_ID`
- Session tokens are stored as SHA-256 digests in PostgreSQL
