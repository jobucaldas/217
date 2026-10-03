# 217

Anticonceptional (birth control) intake tracker with a shared calendar, in English, Português and Español.

- **Client:** Flutter (web, Android, Windows, Linux)
- **API:** Go + PostgreSQL
- **Auth:** WorkOS AuthKit (PKCE; API key server-side only)

Want your data on your own machine? See [Self-hosting](#self-hosting).

## Requirements

Podman and podman-compose on the host. Go and Flutter run in containers — do not install project SDKs on the host.

## Start locally

Copy `.env.example` to ignored `.env.local`. Set `WORKOS_API_KEY` from the WorkOS Dashboard (server-only). `WORKOS_CLIENT_ID` is public. Register redirect URIs:

- `http://localhost:8787/api/auth/workos/callback` (browser)
- `com.jobucaldas.a217://auth/callback` (Android)
- `http://localhost:21717/auth/callback` (Windows and Linux)

```sh
make dev-up       # postgres + Go API + Caddy
make web   # Flutter web → frontend/build/web
```

Open <http://localhost:8787/>. Stop with `make dev-down`.

Host port defaults to **8787** (`HTTP_PORT` / matching `APP_BASE_URL` to override).

## Android

```sh
make test-frontend
make apk
```

Install `frontend/build/app/outputs/flutter-apk/app-debug.apk`. Emulator API base defaults to `http://10.0.2.2:8787` (`--dart-define=API_BASE_URL=...` to override at build time, or **Settings → Advanced options → Self-hosted server URL** in the app).

The published APK has **no built-in server**: on first launch it asks for the address of a 217 server (see [Self-hosting](#self-hosting)), or an invite link from someone who runs one. Release builds only connect over `https://`.

## Windows and Linux

The desktop apps work like the Android one: no built-in server, so they ask for yours on first launch, and sign-in goes through the system browser and returns to a local `http://localhost:21717/auth/callback` listener.

- **Windows:** run `217-nightly-setup.exe` (per-user install, unsigned, so SmartScreen may warn).
- **Linux:** `chmod +x 217-nightly-x86_64.AppImage` and run it. Needs a Secret Service keyring (GNOME Keyring, KWallet) to store the session.

Both are on [GitHub Releases](https://github.com/jobucaldas/217/releases/tag/nightly). Build them yourself with `flutter build windows|linux --release` inside `frontend/` (on the matching OS); `frontend/packaging/` wraps the output into the installer and AppImage.

## Releases

Every push to `main` (after CI is green) publishes the APK, Windows installer, AppImage and GHCR images with the same dual names:
- **nightly** — rolling GitHub Release (`217-nightly.apk`, `217-nightly-setup.exe`, `217-nightly-x86_64.AppImage`) and GHCR tag `:nightly`
- **datetime_sha** — immutable GitHub Release `YYYYMMDDHHMMSS_<shortsha>` (`217-<tag>.<ext>`) and matching GHCR tags

## Layout

| Path | Role |
|---|---|
| `backend/` | Go API; its `Dockerfile` has a `dev` stage (toolchain for compose and `make test-backend`) and the production image |
| `frontend/` | Flutter client for web, Android, Windows and Linux; `Dockerfile` packages the web bundle, `Caddyfile` is the local proxy |
| `docker-compose.yml` | Local stack: Postgres + API + Caddy |
| `.github/workflows/ci.yml` | Backend and Flutter checks; on `main`, publishes GHCR images, the APK, Windows installer and AppImage |

## Validate

```sh
make test-backend
make test-frontend
make web
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
4. Optional branding: in **Branding**, upload `frontend/branding/logo-217-light.svg` (light) and `logo-217-dark.svg` (dark) so the hosted sign-in page shows the 217 wordmark in the app's typeface instead of the app name in WorkOS's default font.

### 2. Configure the server

| Variable | Required | Notes |
|---|---|---|
| `APP_BASE_URL` | yes | Public address people open, e.g. `https://217.example.com`. Used for sign-in redirects, secure cookies and invite links (`APP_BASE_URL/?invite=CODE`). |
| `DATABASE_URL` | yes | e.g. `postgres://app_217:CHANGE_ME@postgres:5432/app_217?sslmode=disable` |
| `WORKOS_CLIENT_ID` | yes | From step 1 |
| `WORKOS_API_KEY` | recommended | From step 1. Sign-in works without it, but **Delete account** needs it to remove the WorkOS login. Server only: never put it in the app or a repo. |
| `SESSION_TTL` | no | Session lifetime, e.g. `720h` |
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` | no | Web push reminders; generate with `make vapid-keys` |

### 3. Run it

- **Compose (simplest):** `docker-compose.yml` runs Postgres, the API and Caddy. Put the variables above in `.env.local`, build the web app with `make web`, then `make dev-up`. Change the default database password and serve it over HTTPS (for example a reverse proxy in front of port 8787, or Caddy itself with your domain in `frontend/Caddyfile` and ports 80/443 published).
- **Images:** CI publishes `app-217-backend` (the API) and `app-217-frontend` (the web bundle in `/app/dist`, to serve with Caddy next to the API) to GHCR on every push to `main`. Put `DATABASE_URL`, `WORKOS_API_KEY` and friends in your orchestrator's secrets.

Check it with `curl https://217.example.com/api/auth/config` — it should answer `{"authkit":true,...,"workos_client_id":"client_..."}`.

### 4. Use it

- **Web:** open your `APP_BASE_URL`. The web app always talks to the server that serves it.
- **Android:** install the APK from [GitHub Releases](https://github.com/jobucaldas/217/releases/tag/nightly). On first launch it asks for your server: type its address (`217.example.com`) or paste an invite link (`https://217.example.com/?invite=CODE`), then **Connect**. The app checks the server, then signs in with the WorkOS client ID the server reports at `/api/auth/config`, so the same APK works with any WorkOS project. Release builds need `https://`.

  To change servers later, sign out and tap **Server: …** on the sign-in screen. Switching servers signs you out, because accounts belong to a server.

  Prefer an APK with your server built in (no setup step)? Build one:

  ```sh
  API_BASE_URL=https://217.example.com make apk
  ```

