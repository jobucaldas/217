# 217

Private bilingual (Português/English) anticonceptional intake tracker. The **Flutter Android** client records taken/missed status and notes. The Go API stores each account's data in PostgreSQL and authenticates users with **WorkOS AuthKit** (PKCE). Opaque, revocable server sessions are returned to the app as bearer tokens (and optionally cookies for browser callbacks).

## Requirements

Only Podman and podman-compose are required on the host. Go and Flutter tooling run inside containers — do not install project SDKs on the host.

## Start locally

Copy `.env.example` to ignored `.env.local`. Set `WORKOS_API_KEY` from the WorkOS Dashboard (server-only). `WORKOS_CLIENT_ID` is public. In WorkOS, register redirect URIs:

- `http://localhost:8080/api/auth/workos/callback` (browser cookie flow)
- `com.jobucaldas.a217://auth/callback` (Flutter Android deep link)

Missing WorkOS configuration is non-fatal at startup; auth endpoints return HTTP 503 until configured.

```sh
make dev-up
```

API: <http://localhost:8080/api/*>. Static notice page: <http://localhost:8080/>.

Stop with `make dev-down`.

## Flutter Android client

```sh
make test-mobile
make mobile-apk
```

Install `mobile/build/app/outputs/flutter-apk/app-debug.apk` on an emulator/device. Emulator default API base is `http://10.0.2.2:8080` (override with `--dart-define=API_BASE_URL=...`).

Sign-in opens WorkOS AuthKit in a Chrome Custom Tab, receives the custom-scheme redirect, and exchanges `code` + `code_verifier` with `POST /api/auth/workos/exchange`. The API key never ships in the APK.

## API

Authentication is WorkOS AuthKit only. The verified WorkOS user id (`user_…`) is the primary identity. Verified emails may auto-link an existing legacy account. Successful exchanges create an opaque, revocable server-side session.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/auth/workos` | Start AuthKit authorization (browser cookie + binding) |
| GET | `/api/auth/workos/callback` | Browser AuthKit callback |
| POST | `/api/auth/workos/exchange` | Native PKCE exchange `{code,code_verifier,redirect_uri}` → `{user,session_token}` |
| GET | `/api/auth/session` | Restore current session (cookie or `Authorization: Bearer`) |
| POST | `/api/auth/logout` | Revoke current session |
| GET | `/api/entries?year=YYYY&month=MM` | Month entries |
| GET/POST | `/api/entries/{YYYY-MM-DD}` | Read/upsert `{taken,notes}` |
| GET | `/api/stats?year=YYYY&month=MM` | Monthly statistics |
| GET/PUT | `/api/reminders/preferences` | Reminder preference (legacy Web Push paths retained) |
| GET | `/api/reminders/vapid-public-key` | Public VAPID status/key |
| POST/DELETE | `/api/reminders/subscriptions` | Push subscription management |

## Container-only validation

```sh
make test-backend
make test-mobile
make mobile-apk
```

## Not verified in this change

- Live WorkOS sign-in against a real AuthKit user in an emulator/device
- Authenticated calendar flow end-to-end with a real session from WorkOS
- Native Android local notifications / FCM replacement for former Web Push reminders

## Security notes

- Never commit `WORKOS_API_KEY` or other secrets
- Flutter receives only `WORKOS_CLIENT_ID` (public) via dart-define / defaults
- Session tokens are stored as SHA-256 digests in PostgreSQL
- Mutating requests remain origin-guarded for cookie clients; native clients use bearer tokens
