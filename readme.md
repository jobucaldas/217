# 217

Anticonceptional (birth control) intake tracker with a shared calendar, in English, Português and Español.

- **Apps:** web, Android, Windows, Linux (Flutter)
- **Server:** Go API + PostgreSQL, behind Caddy
- **Sign-in:** WorkOS AuthKit

Your calendar lives on a server you run. You only need Docker; no clone of this repo.

## Run your own server

**1. WorkOS.** You bring your own sign-in: create a project at [WorkOS](https://workos.com/docs/authkit) and enable AuthKit (free tier is enough). Copy the **Client ID** (public) and an **API key** (secret). Nothing of the maintainers' is built in, and the apps pick up your client ID from your server. Add these redirect URIs, with your public address:

- `https://217.example.com/api/auth/workos/callback` (web)
- `com.jobucaldas.a217://auth/callback` (Android)
- `http://localhost:21717/auth/callback` (Windows, Linux)

Optional: upload `frontend/branding/logo-217-light.svg` / `logo-217-dark.svg` under **Branding** for the hosted sign-in page.

**2. Save this as `compose.yaml`:**

```yaml
name: "217"

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app_217
      POSTGRES_USER: app_217
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app_217 -d app_217"]
      interval: 5s
      timeout: 5s
      retries: 10
    restart: unless-stopped

  backend:
    image: ghcr.io/jobucaldas/217-backend:nightly
    environment:
      DATABASE_URL: postgres://app_217:${POSTGRES_PASSWORD}@postgres:5432/app_217?sslmode=disable
      APP_BASE_URL: ${APP_BASE_URL:?set APP_BASE_URL in .env}
      WORKOS_CLIENT_ID: ${WORKOS_CLIENT_ID:?set WORKOS_CLIENT_ID in .env}
      WORKOS_API_KEY: ${WORKOS_API_KEY:-}
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped

  web:
    image: ghcr.io/jobucaldas/217-frontend:nightly
    environment:
      SITE_ADDRESS: ${SITE_ADDRESS:-:8787}
    ports:
      - "${HTTP_PORT:-8787}:8787"
      # Automatic HTTPS on your own domain: set SITE_ADDRESS=217.example.com
      # in .env and publish these two instead of the line above.
      # - "80:80"
      # - "443:443"
    volumes:
      - caddy:/data
    depends_on:
      - backend
    restart: unless-stopped

volumes:
  pgdata:
  caddy:
```

**3. Save this as `.env` next to it** (keep it private):

```sh
POSTGRES_PASSWORD=change-me
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

- Never commit `WORKOS_API_KEY` or other secrets; the apps only get the public client ID
- Session tokens are stored as SHA-256 digests in PostgreSQL

## Contributing

Developing 217 with your local code: [docs/development.md](docs/development.md).
