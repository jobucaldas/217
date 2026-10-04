# 217

Anticonceptional (birth control) intake tracker with a shared calendar, in English, Português and Español.

- **Apps:** web, Android, Windows, Linux (Flutter)
- **Server:** Go API + PostgreSQL, behind Caddy
- **Sign-in:** WorkOS AuthKit

Your calendar lives on a server you run. You only need Docker; no clone of this repo.

## Self-hosting

**1. WorkOS.** You bring your own sign-in: create a project at [WorkOS](https://workos.com/docs/authkit) and enable AuthKit (free tier is enough). Copy the **Client ID** (public) and an **API key** (secret). Nothing of the maintainers' is built in, and the apps pick up your client ID from your server. Add these redirect URIs, with your public address:

- `https://217.example.com/api/auth/workos/callback` (web)
- `com.jobucaldas.a217://auth/callback` (Android)
- `http://localhost:21717/auth/callback` (Windows, Linux)

Optional: upload `frontend/branding/logo-217-light.svg` / `logo-217-dark.svg` under **Branding** for the hosted sign-in page.

**2. Save this as `compose.yaml`:**

```yaml
name: "217"

services:
  # Private CA + certificates so postgres <-> backend <-> web traffic is encrypted.
  certs:
    image: ghcr.io/jobucaldas/217-backend:nightly
    user: "0:0" # hands the PostgreSQL key to the postgres user
    command: ["-init-tls", "/certs"]
    volumes:
      - certs:/certs

  postgres:
    image: postgres:16-alpine
    command: ["postgres", "-c", "ssl=on", "-c", "ssl_cert_file=/certs/postgres/tls.crt",
              "-c", "ssl_key_file=/certs/postgres/tls.key", "-c", "hba_file=/certs/postgres/pg_hba.conf"]
    environment:
      POSTGRES_DB: "217"
      POSTGRES_USER: "217"
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?create a password and set POSTGRES_PASSWORD in .env}
    volumes:
      - pgdata:/var/lib/postgresql/data
      - certs:/certs:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U 217 -d 217"]
      interval: 5s
      timeout: 5s
      retries: 10
    depends_on:
      certs:
        condition: service_completed_successfully
    restart: unless-stopped

  backend:
    image: ghcr.io/jobucaldas/217-backend:nightly
    environment:
      DATABASE_URL: postgres://217:${POSTGRES_PASSWORD}@postgres:5432/217?sslmode=verify-full&sslrootcert=/certs/ca.crt
      DATA_ENCRYPTION_KEY: ${DATA_ENCRYPTION_KEY:?create a key and set DATA_ENCRYPTION_KEY in .env}
      DATA_ENCRYPTION_KEY_PREVIOUS: ${DATA_ENCRYPTION_KEY_PREVIOUS:-}
      TLS_CERT_FILE: /certs/backend/tls.crt
      TLS_KEY_FILE: /certs/backend/tls.key
      APP_BASE_URL: ${APP_BASE_URL:?set APP_BASE_URL in .env}
      WORKOS_CLIENT_ID: ${WORKOS_CLIENT_ID:?set WORKOS_CLIENT_ID in .env}
      WORKOS_API_KEY: ${WORKOS_API_KEY:-}
    volumes:
      - certs:/certs:ro
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped

  web:
    image: ghcr.io/jobucaldas/217-frontend:nightly
    environment:
      SITE_ADDRESS: ${SITE_ADDRESS:-:8787}
      BACKEND_UPSTREAM: https://backend:3000
      SSL_CERT_DIR: /certs # trust the internal CA for the API hop
    ports:
      - "${HTTP_PORT:-8787}:8787"
      # Automatic HTTPS on your own domain: set SITE_ADDRESS=217.example.com
      # in .env and publish these two instead of the line above.
      # - "80:80"
      # - "443:443"
    volumes:
      - caddy:/data
      - certs:/certs:ro
    depends_on:
      - backend
    restart: unless-stopped

volumes:
  pgdata:
  caddy:
  certs:
```

**3. Save this as `.env` next to it** (keep it private) and fill in every value. Create the database password and the data encryption key yourself (the commands in the comments print good ones); they are only used between the containers, so you never type them again. **Back up `DATA_ENCRYPTION_KEY` apart from the database: without it the data cannot be read.**

```sh
# Create your own database password, e.g. with: openssl rand -hex 24
POSTGRES_PASSWORD=
# Encrypts personal data before it is stored, e.g.: openssl rand -base64 32
DATA_ENCRYPTION_KEY=
APP_BASE_URL=https://217.example.com   # or http://localhost:8787 to try it
WORKOS_CLIENT_ID=client_...
WORKOS_API_KEY=sk_...                  # recommended: "Delete account" needs it
# SITE_ADDRESS=217.example.com         # see the comment in compose.yaml
```

**4. Start it:**

```sh
docker compose up -d
curl http://localhost:8787/api/auth/config   # {"authkit":true,...}
```

Open `APP_BASE_URL`. Update with `docker compose pull && docker compose up -d`; pin `:nightly` to a `YYYYMMDDHHMMSS_<shortsha>` tag to stay on a fixed version. Data is in the `pgdata` volume.

Coming from a version without encryption at rest (no `certs` service in your `compose.yaml`)? Replace `compose.yaml` with the one above, add `DATA_ENCRYPTION_KEY` to `.env`, then pull and start: the first start encrypts the existing data and drops the plaintext. Back up the `pgdata` volume first.

Optional server variables for the `backend` service: `SESSION_TTL` (e.g. `720h`), `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` (web push).

## Get the apps

Download from [GitHub Releases](https://github.com/jobucaldas/217/releases/tag/nightly):

| Platform | File |
|---|---|
| Android | `217-nightly.apk` |
| Windows | `217-nightly-setup.exe` (per-user, unsigned: SmartScreen may warn) |
| Linux | `217-nightly-x86_64.AppImage` (`chmod +x`; needs a keyring such as GNOME Keyring or KWallet) |
| Web | served by your server at `APP_BASE_URL` |

The native apps ship **no built-in server**. On first launch they ask for yours: type its address (`217.example.com`) or paste an invite link (`https://217.example.com/?invite=CODE`), then **Connect**. They sign in with the WorkOS client ID your server reports, so one download works with any server. Release builds need `https://`. To switch servers, sign out and tap **Server: …** on the sign-in screen (switching signs you out).

Every push to `main` publishes the apps and images as `nightly` (rolling) and as an immutable `YYYYMMDDHHMMSS_<shortsha>` release.

## Security

**In transit.** Every hop is TLS:

| Hop | How |
|---|---|
| App or browser → `web` | HTTPS when `SITE_ADDRESS` is your domain (Caddy gets the certificate) or behind your own HTTPS proxy; HSTS on. Release apps only accept `https://` servers |
| `web` → `backend` | `BACKEND_UPSTREAM=https://backend:3000`, verified against the internal CA |
| `backend` → `postgres` | `sslmode=verify-full`; PostgreSQL refuses non-TLS network connections |
| `backend` → WorkOS, push services | HTTPS |

The `certs` service writes a private CA and the `postgres` / `backend` certificates to the `certs` volume on every start, reissuing them before they expire (restart the stack afterwards); the CA key is discarded. Running your own way? `server -init-tls DIR` (`-postgres-hosts`, `-backend-hosts`, `-postgres-uid`, `-backend-uid`) writes the same files, `TLS_CERT_FILE` / `TLS_KEY_FILE` make the API serve HTTPS, and an `https://` `BACKEND_UPSTREAM` with `SSL_CERT_DIR` pointing at the CA makes Caddy verify it.

**At rest.** The API seals personal data with AES-256-GCM before it reaches PostgreSQL: emails, names, every day entry (taken, notes, intimacy, period), partner notes, invite codes, push subscriptions and sign-in secrets. Each value is bound to its row, so it cannot be moved to another user. Lookups use keyed HMAC digests, never the plaintext. What stays readable in the database: ids, dates of logged days, roles, share status, reminder times and timestamps. Session tokens are stored as SHA-256 digests; client IP addresses and user agents are not stored.

**Rotating the key.** Put the current key in `DATA_ENCRYPTION_KEY_PREVIOUS` (comma-separate several), a new one in `DATA_ENCRYPTION_KEY`, restart: the API reseals everything on start. Then remove the old key. The API refuses to start with a key that does not match the stored data.

- Never commit `WORKOS_API_KEY`, `DATA_ENCRYPTION_KEY` or other secrets; the apps only get the public client ID
- The API answers with `Cache-Control: no-store`, and both API and web send `nosniff`, `no-referrer` and anti-framing headers
- Request bodies are capped at 64 KiB; sign-in endpoints are rate limited per address

## Development

Everything runs through Docker Compose (Podman works too); do not install Go or Flutter on the host. The root `docker-compose.yml` builds **your checkout**, unlike the compose file above, which runs the published images.

```sh
cp .env.example .env     # set POSTGRES_PASSWORD (openssl rand -hex 24), DATA_ENCRYPTION_KEY (openssl rand -base64 32) and your WorkOS client ID and API key
docker compose up --build
```

The secrets are declared in `secretspec.toml`: with [SecretSpec](https://secretspec.dev), `secretspec run -- docker compose up --build` reads them from your keyring or password manager instead of `.env`.

Open <http://localhost:8787/>. This writes the internal TLS certificates, then starts Postgres, the Go API (`go run` on the mounted `backend/`) and `web`, which builds the Flutter web app from `frontend/` and serves it with Caddy next to the API. Sign-in needs your own [WorkOS](https://workos.com) project with `http://localhost:8787/api/auth/workos/callback` as a redirect URI; without it the stack runs but nobody can sign in. Change the port with `HTTP_PORT` and a matching `APP_BASE_URL`. Stop with `docker compose down` (`-v` also wipes the database).

| Changed | Do |
|---|---|
| `backend/` | `docker compose restart backend` |
| `frontend/` | `docker compose up --build -d web` |

Checks and tools (Flutter UI needs dark **and** light coverage; `test/theme_contrast_test.dart` and `test/today_nudge_test.dart` must pass):

```sh
docker compose run --rm test-backend    # gofmt, vet, test
docker compose run --rm test-frontend   # flutter analyze + test
docker compose run --rm apk             # debug APK -> frontend/build/app/outputs/flutter-apk/ (API_BASE_URL defaults to the emulator host 10.0.2.2:8787)
docker compose run --rm vapid-keys      # web push key pair
```

Windows and Linux builds need their own OS: `flutter build windows|linux --release` inside `frontend/` (Linux: `clang cmake ninja-build libgtk-3-dev libsecret-1-dev`). `frontend/packaging/` wraps the output into the installer and AppImage that CI publishes. Desktop debug builds default to `http://localhost:8787`.

| Path | Role |
|---|---|
| `backend/` | Go API. `Dockerfile`: `dev` stage (toolchain used by compose) and the production image |
| `frontend/` | Flutter app (web, Android, Windows, Linux). `Dockerfile`: `local` builds the web bundle from source, `prebuilt` (default, what CI publishes) copies `build/web`; `Caddyfile` serves it and proxies `/api/*` (`SITE_ADDRESS`, `BACKEND_UPSTREAM`) |
| `docker-compose.yml` | Dev stack and tooling |
| `.github/workflows/ci.yml` | Checks on every PR; on `main`, publishes the GHCR images and the app releases |
