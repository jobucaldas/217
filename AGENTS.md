Project: 217

Cross-platform application for tracking anticonceptional intake.

## Overview
Cross-platform app for tracking anticonceptional intake via a dynamic, scrollable calendar UI. Features multi-user support with password-based authentication, dark mode, and multi-language (Pt/En) support.

## Tech Stack
- Frontend: Dioxus (Rust/WASM) — cross-platform web app
- Backend: Go — REST API
- Database: PostgreSQL 16 — containerized via Podman
- Reverse Proxy: Caddy — serves frontend, proxies API

## Development Environment
Fully containerized with Podman and Podman-Compose. DO NOT install anything on the host machine. All tooling runs inside containers (PostgreSQL, Go backend, Rust frontend).
- Dev container includes Go 1.25, Rust 1.75+, wasm-bindgen-cli, postgresql-client.

### Starting the environment
```sh
# Build frontend WASM and start all services
make dev-up

# Or manually:
cd frontend && ./build.sh
podman-compose up -d
```
Open **http://localhost:8080** to use the app.

## Architecture Diagram
```
┌──────────┐    :8080    ┌───────┐   /api/*    ┌──────────┐     SQL    ┌────────────┐
│ Browser  │ ──────────> │ Caddy │ ──────────> │  Go API  │ ─────────> │ PostgreSQL │
│ (WASM)   │ <────────── │       │ <────────── │  (:3000) │ <───────── │            │
└──────────┘             └───────┘             └──────────┘            └────────────┘
                           │
                           │  / → serve frontend dist/
                           └──────────────────────────────────
```

## API Endpoints

### Auth (no auth required)
- `POST /api/auth/register` — `{email, name, password}` → `{user, api_key}`
- `POST /api/auth/login` — `{email, password}` → `{user, api_key}`
- `POST /api/auth/change-password` — `{old_password, new_password}` (requires `X-API-Key`) → `{"status": "ok"}`

### Entries (require `X-API-Key` header)
- `GET /api/entries?year=YYYY&month=MM` — list user's entries for a month
- `GET /api/entries/{date}` — get entry for specific date
- `POST /api/entries/{date}` — upsert entry `{taken, notes}`
- `GET /api/stats?year=YYYY&month=MM` — monthly stats (taken/missed/streak)

## Data Model
```sql
users (id UUID PK, email UNIQUE, name, api_key UNIQUE, password_hash TEXT, created_at, updated_at)
entries (id UUID PK, user_id FK->users, date, taken, notes, UNIQUE(user_id, date), created_at, updated_at)
```

## Store Interface
Both `MemoryStore` and `PGStore` implement `store.Store` with methods: `CreateUser`, `GetUserByAPIKey`, `GetUserByEmail`, `VerifyPassword`, `ChangePassword`, `GetEntry`, `ListEntries`, `UpsertEntry`, `GetStats`, `Close`.

## New Features Implemented
### Infinite Scroll Calendar
- Replaced month-by-month navigation with a vertically scrollable list of months.
- Automatically loads past/future months as the user scrolls near the edges.
- On first load, automatically scrolls to the current month for convenience.

### Day Modal Popup
- Clicking any day on the calendar (past or present) opens a modal.
- Allows toggling the "taken" status (✓ Taken / ✗ Missed buttons).
- Provides a textarea to add or edit notes for that specific day.
- "Save" and "Cancel" buttons for interaction.

### Enhanced Visual Indicators
- Days are clearly marked directly on the calendar grid:
    - **Green background + large ✓** for days when medication was taken.
    - **Red background + large ✗** for days when medication was missed (entry exists but `taken=false`).
    - **Transparent background** for days with no entry recorded.
    - **Gray background** for future dates (not clickable).
- Text color on marked days adjusts to white for better readability.

### Options Menu
- Accessible via a "☰" hamburger icon in the app header.
- **Dark Mode Toggle**: Switches between light and dark themes using CSS variables. Dark mode is the default.
- **Language Toggle**: Switches the app's display language between Portuguese (default) and English.
- **Change Password**: A form to securely update the user's password (requires current and new password, new password min 6 chars).
- **Logout**: Clears authentication state and returns to the login/register screen.

### Authentication & Reactivity Improvements
- Login/Register forms are now more robust, ensuring input is properly sent to the backend.
- Calendar entries now load correctly and react dynamically to login/logout events and manual entry updates.

## Project Structure
```
217/
├── notes.md                 # This file
├── docker-compose.yml       # PostgreSQL + backend + Caddy
├── Makefile                 # Build & test targets
├── backend/                 # Go API server
│   ├── Dockerfile           # Container image (Go 1.25)
│   ├── cmd/server/          # Entrypoint with -db flag
│   ├── db/                  # SQL migrations (embedded: 001_users, 002_entries, 003_password_hash)
│   └── internal/
│       ├── server/          # HTTP server & routing
│       ├── handler/         # Auth middleware + route handlers
│       ├── model/           # User (with password_hash), Entry, Stats, Auth/ChangePassword requests
│       └── store/           # Store interface + memory/pg impls (with password logic)
├── frontend/                # Dioxus Rust app
│   ├── build.sh             # Build WASM binary + bindings
│   ├── dist/                # WASM output (gitignored)
│   └── src/
│       ├── api.rs           # HTTP client with absolute URLs, auth headers
│       ├── models.rs        # Shared types (AuthState, ChangePasswordRequest, Lang enum)
│       ├── i18n.rs          # Translation system (Pt/En strings)
│       ├── components/
│       │   ├── auth.rs      # Login/register screen (i18n, robust form)
│       │   ├── calendar.rs  # Infinite-scroll calendar grid (i18n, indicators, scroll-to-today)
│       │   ├── day_modal.rs # Day click popup (i18n, toggle + notes)
│       │   └── options_menu.rs # Dark mode, change password, language toggle
│       └── main.rs          # App shell with auth/dark mode/language context, scroll logic
├── dev/                     # Dev scripts
├── Caddyfile                # Reverse proxy config
└── .devcontainer/
    ├── Dockerfile           # Dev container (Go + Rust + wasm-bindgen-cli)
    └── devcontainer.json    # VS Code config
```

## Testing
| Category | Status | Notes |
|----------|--------|-------|
| Go build | ✅ Zero warnings, zero errors | `go build ./...`, `go vet ./...` |
| Rust build | ✅ Zero warnings, zero errors | `cargo build --target wasm32-unknown-unknown --release` |
| Go tests | ✅ 16/16 passed | `go test ./... -v` |
| Rust tests | ✅ 6/6 passed | `cargo test` |
| Frontend assets | ✅ HTML, JS, WASM served (HTTP 200) | `curl http://localhost:8080/...` |
| Full E2E Flow | ✅ Passed all 7 steps | Register, toggle, list, change password, login with new password, assets |

## Security Audit Summary
| Area | Status | Notes |
|------|--------|-------|\
| Password hashing | ✅ bcrypt (cost 10) | Industry standard |\
| API key generation | ✅ crypto/rand (128-bit) | Cryptographically random |\
| SQL injection | ✅ Parameterized queries | All PGStore queries use `$1, $2` |\
| Input validation | ✅ Email format, password length | Backend validates both |\
| Auth tokens | ✅ X-API-Key header | No cookies, CSRF-safe |\
| Error messages | ✅ Safe | Login: "invalid email or password" |\
| CORS | ⚠️ `*` origin | Acceptable for API-key auth in dev, but should be tightened for prod |\
| No HTTPS | ⚠️ Dev only | Caddy auto-TLS in production handles this |\
| No rate limiting | ❌ Missing | Should add on `/api/auth/*` endpoints to prevent brute-force |\
| API keys never expire | ❌ Missing | Key rotation and expiry mechanism needed for long-lived sessions |\
| No email verification | ❌ Missing | Anyone can register; email verification flow needed |\
| No audit logging | ❌ Missing | Structured event logging for security-sensitive actions is beneficial |\
| API key persistence | ⚠️ Memory-only | Frontend API key is lost on page refresh (user must re-login). Could use `sessionStorage` for convenience but with XSS risk note. |\
| Dioxus XSS | ✅ Auto-escapes | Frontend renders user input safely |\

### Backend security recommendations (implemented)
- Password min 6 chars validated at handler level.
- Email format validated (contains `@` and `.`).
- Error messages never reveal whether email or password was wrong.
- `PasswordHash` field excluded from JSON via `json:"-"`.

### Frontend security notes
- API key stored only in WASM memory (not `localStorage`). Lost on page refresh — user must re-login. This is currently more secure than `localStorage` but less convenient.
- Dioxus escapes all rendered content (XSS-safe).

## Future Plans
- [ ] Implement persistent sessions and/or refresh token flow.
- [ ] Add API key rotation and expiry mechanism.
- [ ] Implement rate limiting on authentication endpoints to prevent brute-force attacks.
- [ ] Develop an email verification flow for new user registrations.
- [ ] Implement a feature to **grant read-only access to trusted contacts** for specific calendar data.
- [ ] Add push notifications for anticonceptional reminders.
- [ ] Implement data synchronization across multiple devices.
- [ ] Develop a dashboard with charts and analytics for usage patterns.
- [ ] Integrate OAuth login options (e.g., Google, Apple).
- [ ] Explore dedicated mobile builds using Dioxus mobile capabilities.
- [ ] Implement multi-factor authentication (MFA) for enhanced security.
- [ ] Add more comprehensive internationalization (i18n) for new features and dynamic content.
