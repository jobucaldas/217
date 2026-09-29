# Authorized Nix development path

For this task the owner authorized Nix instead of the older container-only rule.
The container workflow remains available. No host/global tool installation is needed.
The committed `flake.lock` pins nixpkgs and the Rust overlay. Run these commands
from the repository root:

```sh
nix flake lock path:.
nix develop path:.
sh dev/nix-setup.sh
```

Retain `flake.lock` for reproducibility. The lock pins nixpkgs and the Rust
overlay, including its stable Rust manifest. `path:.` also works while the new
project files remain untracked.
Go is 1.25 as required by go.mod. Rust includes the WASM target. The setup script
installs wasm-bindgen-cli **0.2.121**, matching frontend/Cargo.lock, into `.dev-tools`.
Enter the shell at the repo root so its PATH finds this directory.
Playwright uses Nix Chromium explicitly to avoid incompatible downloaded Linux
executables; the npm driver remains pinned by e2e/package-lock.json. Browser/driver
compatibility needs the parent browser run. PostgreSQL 16 and Caddy are included.

## Official Google asset

Login uses Google's unchanged pre-approved light rectangular PNG from the
[branding guidelines](https://developers.google.com/identity/branding-guidelines).
It is vendored as `frontend/static/google-signin.png` so login does not depend on
a third-party request. Source URL:
https://developers.google.com/static/identity/gsi/web/images/standard-button-white.png
SHA-256: `892062091f35e69dd838ba4a4f238d37a0562d52ecda6406eb343a1127251409`.

The complete image preserves the official logo, lettering and proportions; no G
is drawn or recolored. The accessible link label and image alternative are Pt/En;
the official image lettering is English. The anchor remains `/api/auth/google`.
The official bundle is https://developers.google.com/static/identity/images/signin-assets.zip.

## Parent validation

```sh
(cd backend && go mod tidy && gofmt -w internal/auth internal/store internal/handler api_test.go cmd/e2esession)
(cd backend && go mod verify && go test -race ./... && go vet ./... && go build ./...)
(cd frontend && cargo fmt && cargo test --locked && cargo clippy --locked --all-targets -- -D warnings && ./build.sh)
```

The new go-oidc dependency requires `go mod tidy` to update go.sum and indirect
dependencies; no Go commands were executed by the source editor. Use a disposable
PostgreSQL database for migration/integration checks. Start the API with `go run
./cmd/server -addr :3000 -db "$DATABASE_URL"` from backend, and serve frontend/dist through
Caddy with `/api/*` reverse-proxied to localhost:3000. Do not reuse the compose-only
Caddy upstream name `backend` for a Nix process. With the app on localhost:8080:

```sh
SESSION_TOKEN=$(cd backend && go run ./cmd/e2esession -db "$DATABASE_URL")
export SESSION_TOKEN
BASE_URL=http://localhost:8080 OUTPUT_DIR="$PWD/artifacts/screenshots" node e2e/screenshots.js
unset SESSION_TOKEN
git diff --check
git diff --cached --name-only
```

For PostgreSQL contract tests, export `TEST_DATABASE_URL` as a PostgreSQL URL for
a disposable database before `go test`; the test creates and removes its own schema
and applies every migration. Without this variable the PostgreSQL case is skipped.

Validated with the pinned Nix shell: Go format/module verification/race tests/vet/build,
Rust format/tests/clippy/WASM build, PostgreSQL identity contract tests, migration 011,
and all seven Playwright screenshots. The final independent review found no P0/P1 issues.
