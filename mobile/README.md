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
| `API_BASE_URL` | web: same-origin; Android debug: `http://10.0.2.2:8787`; Android release: none | Emulator → host Caddy. Release APKs without it ask for a server on first launch |
| `WORKOS_CLIENT_ID` | staging public client id | Fallback only: Android signs in with the client id the server reports at `/api/auth/config` |
| `WORKOS_REDIRECT_URI` | `com.jobucaldas.a217://auth/callback` | Android deep link only |
| `SELF_HOST_GUIDE_URL` | repo README `#self-hosting` | Linked from the web sign-in card and the Android server setting |

## Choosing a server (Android)

Release APKs built without `API_BASE_URL` (like the published nightly) ship with no server. On first launch, `ServerSetupScreen` asks for one: a bare host gets `https://`, a pasted invite link (`…/?invite=CODE`) sets the server and keeps the invite for after sign-in, and **Connect** only saves a server whose `/api/auth/config` answers with AuthKit on. Release builds refuse `http://` (the release manifest blocks cleartext). Signed out, tapping **Server: …** on the sign-in screen opens the same screen to switch.

Builds with an `API_BASE_URL` (debug, or your own) skip that screen; there the sign-in screen links to **Settings → Advanced options → Self-hosted server URL** instead (leave it empty to use the built-in server).

Either way the server is chosen only while signed out, and switching servers signs you out, since accounts belong to a server. The web build always talks to the server that serves it, so none of this shows there.

## Calendar invites

The owner's **Settings → Share calendar** creates an invite with a link (`APP_BASE_URL/?invite=CODE`, returned by the API as `invite_url`) and a code. On Android, **Send invite** opens the system share sheet (WhatsApp, SMS…) through the `com.jobucaldas.a217/share` platform channel in `MainActivity.kt`; elsewhere it copies the link. Opening the link in the web app remembers the code across sign-in and then offers to join. Anyone with nothing shared yet can also use **Join a calendar with a code** in Settings.

Never pass `WORKOS_API_KEY` into the app.
