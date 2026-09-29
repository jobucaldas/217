# 217 Flutter (Android)

Native Android client for the 217 API. Auth uses WorkOS AuthKit with PKCE; the WorkOS API key stays on the Go server.

## Container commands

From the repository root:

```sh
make test-mobile
make mobile-apk
```

Do not install Flutter on the host.

## Dart defines

| Define | Default | Notes |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:8080` | Emulator → host Caddy |
| `WORKOS_CLIENT_ID` | staging public client id | Public OAuth client id |
| `WORKOS_REDIRECT_URI` | `com.jobucaldas.a217://auth/callback` | Must be allow-listed in WorkOS |

Never pass `WORKOS_API_KEY` into the app.
