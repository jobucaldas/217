# Development

Everything runs in containers through Docker Compose (Podman works too). Do not install Go or Flutter on the host. This builds **your checkout**; to just run 217, use the compose file in the [README](../readme.md).

## Run the stack from local code

```sh
cp .env.example .env     # set WORKOS_API_KEY; the client ID is public
docker compose up --build
```

Open <http://localhost:8787/>. This starts Postgres, the Go API (`go run` on the mounted `backend/`) and `web`, which builds the Flutter web app from `frontend/` and serves it with Caddy next to the API.

| Changed | Do |
|---|---|
| `backend/` | `docker compose restart backend` |
| `frontend/` | `docker compose up --build -d web` |

Register `http://localhost:8787/api/auth/workos/callback` as a redirect URI in WorkOS. Change the port with `HTTP_PORT` and a matching `APP_BASE_URL`. Stop with `docker compose down` (`-v` also wipes the database).

## Checks

```sh
docker compose run --rm test-backend    # gofmt, vet, test
docker compose run --rm test-frontend   # flutter analyze + test
```

Flutter UI needs dark **and** light coverage; `test/theme_contrast_test.dart` and `test/today_nudge_test.dart` must pass.

## Other tools

```sh
docker compose run --rm apk            # debug APK -> frontend/build/app/outputs/flutter-apk/ (API_BASE_URL defaults to the emulator host 10.0.2.2:8787)
docker compose run --rm vapid-keys     # web push key pair
```

Windows and Linux builds need their own OS: `flutter build windows|linux --release` inside `frontend/` (Linux: `clang cmake ninja-build libgtk-3-dev libsecret-1-dev`). `frontend/packaging/` wraps the output into the installer and AppImage CI publishes. Desktop debug builds default to `http://localhost:8787`.

## Layout

| Path | Role |
|---|---|
| `backend/` | Go API. `Dockerfile`: `dev` stage (toolchain used by compose) and the production image |
| `frontend/` | Flutter app (web, Android, Windows, Linux). `Dockerfile`: `local` builds the web bundle from source, `prebuilt` (default, what CI publishes) copies `build/web`; `Caddyfile` serves it and proxies `/api/*` |
| `docker-compose.yml` | Dev stack and tooling (this file) |
| `.github/workflows/ci.yml` | Checks on every PR; on `main`, publishes GHCR images and the app releases |

The web image configures itself with `SITE_ADDRESS` (default `:8787`) and `BACKEND_UPSTREAM` (default `backend:3000`).

## Releases

CI builds the web bundle once and publishes the `prebuilt` image. Releases also carry the APK, Windows installer and AppImage; see the [README](../readme.md#get-the-apps).
