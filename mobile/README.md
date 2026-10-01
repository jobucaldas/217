# 217 Flutter (Android + web)

Flutter client for the 217 API. Auth uses WorkOS AuthKit with PKCE; the WorkOS API key stays on the Go server.

## Web tryout (easiest)

With the stack up (`make dev-up` from the repo root):

```sh
make mobile-web
```

Open <http://localhost:8787/>. Sign-in hits `GET /api/auth/workos` (same origin), shows a same-origin **Continue** handoff page styled like the 217 login screen (click required so Chromium keeps the binding cookie), then AuthKit (branded to match), then `/api/auth/workos/callback` which sets the session cookie and returns you to the app.

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

Never pass `WORKOS_API_KEY` into the app.
