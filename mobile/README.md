# 217 Flutter (Android + web)

Flutter client for the 217 API. Auth uses WorkOS AuthKit with PKCE; the WorkOS API key stays on the Go server.

## Web tryout (easiest)

With the stack up (`make dev-up` from the repo root):

```sh
make mobile-web
```

Open <http://localhost:8787/>. Sign-in fetches `GET /api/auth/workos` (JSON + binding cookie), then navigates once to AuthKit (branded to match 217). Callback `/api/auth/workos/callback` sets the session cookie and returns you to the app — no second continue screen.

Web defaults to an empty `API_BASE_URL` (same origin). Browser HTTP uses credentials so the session cookie is sent.

Caddy binds host **8787** by default (avoids :8080 clashes). Override with `HTTP_PORT=…` and a matching `APP_BASE_URL` / WorkOS redirect URI.

## Android

```sh
make test-mobile
make mobile-apk
```

Do not install Flutter on the host.

## Dart defines

| Define | Default | Notes |
|---|---|---|
| `API_BASE_URL` | web: same-origin; Android: `http://10.0.2.2:8787` | Emulator → host Caddy |
| `WORKOS_CLIENT_ID` | staging public client id | Public OAuth client id |
| `WORKOS_REDIRECT_URI` | `com.jobucaldas.a217://auth/callback` | Android deep link only |
| `SELF_HOST_GUIDE_URL` | repo README `#self-hosting` | Linked from the web sign-in card and the Android server setting |

On Android, people who host their own 217 server can point the app at it before signing in: the sign-in screen links to **Settings → Advanced options → Self-hosted server URL** (leave it empty to use the `API_BASE_URL` baked into the build). The option is only offered while signed out, and switching servers signs you out, since accounts belong to a server. The web build always talks to the server that serves it, so the option is hidden there.

## Calendar invites

The owner's **Settings → Share calendar** creates an invite with a link (`APP_BASE_URL/?invite=CODE`, returned by the API as `invite_url`) and a code. On Android, **Send invite** opens the system share sheet (WhatsApp, SMS…) through the `com.jobucaldas.a217/share` platform channel in `MainActivity.kt`; elsewhere it copies the link. Opening the link in the web app remembers the code across sign-in and then offers to join. Anyone with nothing shared yet can also use **Join a calendar with a code** in Settings.

Never pass `WORKOS_API_KEY` into the app.
