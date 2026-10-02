# 217

Private anticonceptional intake tracker in English, Português and Español.

- **Client:** Flutter (web + Android)
- **API:** Go + PostgreSQL
- **Auth:** WorkOS AuthKit (PKCE; API key server-side only)

Want your data on your own machine? See [Self-hosting](#self-hosting).

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

## Self-hosting

You can run your own 217 server, so your calendar never leaves hardware you control. A server is three pieces behind one origin:

| Piece | What it is |
|---|---|
| PostgreSQL 16 | Stores accounts, entries, invites and notes |
| Go API (`backend/`) | Serves `/api/*`; runs database migrations on startup |
| Caddy | Serves the Flutter web app at `/` and proxies `/api/*` to the API |

### 1. Create a WorkOS project

Sign-in uses [WorkOS AuthKit](https://workos.com/docs/authkit) (free tier is enough for personal use).

1. Create a project and enable AuthKit.
2. Copy the **Client ID** (public) and an **API key** (secret, server only).
3. Add redirect URIs for your public address, for example:
   - `https://217.example.com/api/auth/workos/callback` (web)
   - `com.jobucaldas.a217://auth/callback` (Android app)

### 2. Configure the server

| Variable | Required | Notes |
|---|---|---|
| `APP_BASE_URL` | yes | Public address people open, e.g. `https://217.example.com`. Used for sign-in redirects, secure cookies and invite links (`APP_BASE_URL/?invite=CODE`). |
| `DATABASE_URL` | yes | e.g. `postgres://app_217:CHANGE_ME@postgres:5432/app_217?sslmode=disable` |
| `WORKOS_CLIENT_ID` | yes | From step 1 |
| `WORKOS_API_KEY` | yes | From step 1. Never put it in the app or a public repo. |
| `SESSION_TTL` | no | Session lifetime, e.g. `720h` |
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` | no | Web push reminders; generate with `make vapid-keys` |

### 3. Run it

- **Compose (simplest):** `docker-compose.yml` runs Postgres, the API and Caddy. Put the variables above in `.env.local`, build the web app with `make mobile-web`, then `make dev-up`. Change the default database password and serve it over HTTPS (for example a reverse proxy in front of port 8787, or Caddy itself with your domain in the `Caddyfile` and ports 80/443 published).
- **Kubernetes:** `deploy/kustomize/base` has backend and frontend deployments plus a production `Caddyfile`; see `deploy/kustomize/overlays/dev` for a working overlay. Put `DATABASE_URL`, `WORKOS_API_KEY` and friends in a Secret.
- **Images:** CI publishes `app-217-backend` and `app-217-frontend` images to GHCR on every push to `main`.

Check it with `curl https://217.example.com/api/auth/config` — it should answer `{"authkit":true,...}`.

### 4. Use it

- **Web:** open your `APP_BASE_URL`. The web app always talks to the server that serves it.
- **Android:** the app signs in with the WorkOS client ID it was built with. With your own WorkOS project, build your own APK pointed at your server:

  ```sh
  API_BASE_URL=https://217.example.com WORKOS_CLIENT_ID=client_... make mobile-apk
  ```

  Any build can also switch servers before signing in: on the sign-in screen tap **Hosting your own 217 server?** → **Self-hosted server URL**, then **Test connection** and **Save**. That works when the server uses the same WorkOS client ID as the app. Switching servers signs you out, because accounts belong to a server.

