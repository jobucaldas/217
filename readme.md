# 217

A private, bilingual (Português/English) anticonceptional intake tracker. The Dioxus WebAssembly PWA records taken/missed status and notes. The Go API stores each account's data, reminder preference, and Web Push subscriptions in PostgreSQL. A server-side scheduler sends one push per subscription and local reminder date; the service worker displays it even when the page is closed.

## Requirements

Only Podman and podman-compose are required on the host. Go, Rust, PostgreSQL clients, wasm-bindgen, and browser tooling run in containers.

## Start locally

Copy `.env.example` to the ignored `.env.local` and configure `APP_BASE_URL`, `GOOGLE_CLIENT_ID`, and `GOOGLE_CLIENT_SECRET`. In Google Cloud, register the exact callback `${APP_BASE_URL}/api/auth/google/callback`. Missing OAuth configuration is non-fatal at startup; the Google login endpoint returns HTTP 503.

```sh
make dev-up
```

Open <http://localhost:8080>. `localhost` is a browser secure-context exception, so service workers and Push can be developed there. `http://192.168.x.x:8080` is **not** a secure context and cannot be used for Android Push; use a trusted HTTPS hostname for a physical device.

Stop with `make dev-down`.

## Web Push / VAPID configuration

Generate a key pair inside the pinned development container:

```sh
make vapid-keys
```

Prefer adding the generated values and a real contact to the consolidated, ignored `.env.local`. Never commit the private key. The legacy `.env.reminders.local` is also loaded when present; if both files exist, `.env.local` is loaded last and overrides it.

```dotenv
VAPID_PUBLIC_KEY=replace-with-generated-public-key
VAPID_PRIVATE_KEY=replace-with-generated-private-key
VAPID_SUBJECT=mailto:notifications@example.com
```

`make dev-up` automatically passes these environment files when they exist. The server fails closed for incomplete/malformed keys or a subject that is not `mailto:`/`https:`. Keep the key pair stable: rotating it requires browsers to subscribe again. With no keys, tracking still works and the UI truthfully reports that notifications are unavailable.

Reminder semantics:

- preferences and subscriptions are authenticated and user-scoped;
- enabling requires a saved browser subscription;
- the IANA timezone is captured from the browser;
- the server checks due reminders every 30 seconds;
- a persistent `(subscription, local date)` delivery record prevents repeat sends;
- send claims have a five-minute crash-recovery lease and failed sends use bounded exponential retry;
- HTTP 404/410 Push responses remove expired subscriptions;
- outbound Push uses a 15-second timeout, rejects redirects, and will not dial private/loopback/link-local addresses.

Web Push is best-effort, not an exact Android alarm. Delivery may be delayed by connectivity, browser/vendor services, Doze, or OEM battery policy. Force-stopping Chrome may suppress Push until it is reopened.

## Android PWA install and permission

1. Deploy through Caddy (or another reverse proxy) on a trusted HTTPS hostname.
2. Open the site in Android Chrome and register/login.
3. Choose **Install app** when offered, or Chrome menu → **Add to Home screen / Install app**.
4. Open the installed app, menu **☰** → **Daily reminder**.
5. Choose time, then tap **Enable reminder on this device**. This user gesture requests notification permission and creates the Push subscription.
6. If permission is denied, open Android Settings → Apps → Chrome/217 → Notifications, or Chrome site settings, and allow notifications before retrying.
7. Close the page (do not force-stop Chrome) and test with a reminder several minutes ahead.

Disabling persists the disabled preference first, then removes the server endpoint and browser subscription. Logout also unsubscribes this device so a shared phone does not continue receiving the previous account's reminders.

## Android emulator validation

When you need closed-page Android Web Push evidence, use the container-only Nix harness under `dev/android-emulator/`.

```sh
make dev-down
make vapid-keys > .env.reminders.local
make dev-up
dev/android-emulator/run.sh validate
```

Cleanup:

```sh
dev/android-emulator/run.sh cleanup || true
make dev-down
rm -f .env.reminders.local
rm -rf artifacts/android
```

Limitations:
- the first Nix build is large and may take several minutes;
- the emulator image must include Chrome and Google Play Services;
- `adb reverse` only proves localhost development, not production HTTPS;
- Web Push on Android remains best-effort and can be delayed by Play Services, Chrome, or Doze.

## API

Authentication is Google-only. The verified Google subject is the primary identity. Only authoritative Google email claims may auto-link an existing legacy account; external email collisions require independent ownership verification. OAuth uses one-time expiring browser-bound state, an independent nonce, validated ID tokens and PKCE S256. Successful callbacks create an opaque, revocable server-side session and set an HttpOnly cookie; no token is exposed to WASM or JavaScript.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/auth/google` | Start Google authorization |
| GET | `/api/auth/google/callback` | Exact Google callback |
| GET | `/api/auth/session` | Restore current session |
| POST | `/api/auth/logout` | Revoke current session |
| GET | `/api/entries?year=YYYY&month=MM` | Month entries |
| GET/POST | `/api/entries/{YYYY-MM-DD}` | Read/upsert `{taken,notes}` |
| GET | `/api/stats?year=YYYY&month=MM` | Monthly statistics |
| GET/PUT | `/api/reminders/preferences` | Read/update `{enabled,time,timezone}`; response includes `subscription_count` and `deliverable` |
| GET | `/api/reminders/vapid-public-key` | Public configuration status/key |
| POST/DELETE | `/api/reminders/subscriptions` | Save/remove this account's Push endpoint |

## Container-only validation

```sh
# Build the pinned tool image
podman build -t localhost/217-dev -f .devcontainer/Dockerfile .

# Backend format, deterministic tests (including scheduler), race, vet, build
podman run --rm -v "$PWD:/workspace:Z" -w /workspace/backend localhost/217-dev \
  sh -c 'test -z "$(gofmt -l .)" && go mod verify && go test -mod=readonly -race ./... -v && go vet -mod=readonly ./... && go build -mod=readonly ./...'

# Rust tests/lints and complete release PWA build
podman run --rm -v "$PWD:/workspace:Z" -w /workspace/frontend localhost/217-dev \
  sh -c 'cargo fmt -- --check && cargo test --locked && cargo clippy --locked --all-targets -- -D warnings && ./build.sh'

# Disposable compose-backed API and static PWA smoke tests
podman-compose -p 217-validation up -d --build
# run the curl/browser checks documented in artifacts/test-results, then:
podman-compose -p 217-validation down -v
```

`frontend/build.sh` rebuilds `dist/` with `index.html`, initialized WASM, bridge JS, service worker, manifest, and 192/512 icons. The worker never caches `/api/*`.

## Screenshot reproduction

Screenshots are generated artifacts under `artifacts/screenshots/` and are intentionally ignored by Git. With the stack running, use the pinned Playwright image:

First seed a short-lived test session using database access (this command does not add a production HTTP route), then pass the printed token only to Playwright as `SESSION_TOKEN`:

```sh
SESSION_TOKEN=$(podman-compose exec -T backend sh -lc 'go run ./cmd/e2esession -db "$DATABASE_URL"')
podman run --rm --network host \
  -e BASE_URL=http://localhost:8080 -e OUTPUT_DIR=/artifacts/screenshots \
  -e SESSION_TOKEN="$SESSION_TOKEN" \
  -e PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
  -v "$PWD/e2e:/work:Z" -v "$PWD/artifacts:/artifacts:Z" -w /work \
  mcr.microsoft.com/playwright:v1.62.1-noble \
  sh -c 'npm ci --ignore-scripts && npm run screenshots'
```

The checked-in script captures auth/onboarding, main/today, a day dialog with notes, and fully loaded reminder settings at 360×800, plus 320×568 stress captures. It fails instead of saving the reminder screenshot if the settings API never finishes loading.

## Security and deployment notes

Before enabling Google login on a database upgraded from legacy password authentication, check for case-insensitive duplicate emails:

```sql
SELECT LOWER(email) AS normalized_email, COUNT(*) AS account_count, ARRAY_AGG(id ORDER BY created_at) AS user_ids
FROM users
GROUP BY LOWER(email)
HAVING COUNT(*) > 1;
```

Resolve each group deliberately (merge/reassign dependent data and identities according to your retention policy, then rename or remove the duplicate account) and rerun the query until it returns no rows. Until resolved, Google login for an affected normalized email fails closed with an ambiguous-email error; other accounts continue to work. Back up PostgreSQL before any merge.

Session tokens are stored in PostgreSQL only as SHA-256 digests. Cookies use `HttpOnly`, `SameSite=Lax`, `Path=/`, an expiry/Max-Age, and `Secure` for HTTPS `APP_BASE_URL`. Mutating requests are origin-guarded and credentialed CORS is restricted to that configured origin. Legacy password and API-key columns/data remain for migration compatibility but have no public auth routes. PostgreSQL must be backed up. Production should use HTTPS, stable secrets, rate limiting, and normal backup/monitoring. No secret values belong in source, screenshots, or logs.


### Settings and Google account ownership

Use the separate **Configurações / Settings** header button for theme, language and
daily reminders; **Voltar ao calendário / Back to calendar** preserves the mounted
calendar. The hamburger contains only Logout. Failed server logout keeps the
session visible and offers retry.

Google ID tokens are verified server-side with `coreos/go-oidc` (Google JWKS,
issuer, audience, expiry, subject and per-attempt nonce). Authorization retains
PKCE and one-time browser-bound state. The application issues its own revocable
HttpOnly session; it requests no offline access or refresh tokens.

Google subject identifies an account. Email can automatically link a legacy
account only when Google is authoritative (verified Gmail or verified hosted-domain
email). External email without `hd` can create a new account, but cannot inherit
an existing account. If linking fails, contact the app operator for independent
ownership verification. Operators must not bypass this check based solely on a
Google verified external email, or merge ambiguous normalized emails automatically.
No self-service recovery/linking endpoint is provided.

Sources: [Google OIDC](https://developers.google.com/identity/openid-connect/openid-connect),
[branding and asset provenance](dev/NIX.md). See [Nix setup and validation](dev/NIX.md)
for the optional workspace development environment; containers remain supported.
