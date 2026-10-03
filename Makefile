DEV_IMAGE ?= localhost/217-dev
FLUTTER_IMAGE ?= ghcr.io/cirruslabs/flutter:stable
FRONTEND_DIR = frontend
GO_RUN = podman run --rm -v "$(CURDIR)/backend:/app:Z" -w /app $(DEV_IMAGE)
# -e passes API_BASE_URL / WORKOS_CLIENT_ID from the host when set (dart-defines below).
FLUTTER_RUN = podman run --rm -e API_BASE_URL -e WORKOS_CLIENT_ID -v "$(CURDIR)/$(FRONTEND_DIR):/workspace:Z" -w /workspace $(FLUTTER_IMAGE) bash -lc
FLUTTER_PREP = git config --global --add safe.directory /sdks/flutter >/dev/null 2>&1 || true; flutter pub get
WORKOS_CLIENT_ID_DEFAULT = client_01M3QCMK75B35RPC8EAJA5GREP
COMPOSE_ENV = $(if $(wildcard .env.reminders.local),--env-file .env.reminders.local,) $(if $(wildcard .env.local),--env-file .env.local,)

.PHONY: dev-image test-backend test-frontend test dev-up dev-down dev-logs vapid-keys apk web

# Go toolchain image: the `dev` stage of backend/Dockerfile.
dev-image:
	podman build --target dev -t $(DEV_IMAGE) backend

test-backend: dev-image
	$(GO_RUN) sh -c 'test -z "$$(gofmt -l .)" && go vet -mod=readonly ./... && go test -mod=readonly ./...'

test-frontend:
	$(FLUTTER_RUN) '$(FLUTTER_PREP) && flutter analyze && flutter test'

test: test-backend test-frontend

dev-up: dev-image
	podman-compose $(COMPOSE_ENV) up -d --build

dev-down:
	podman-compose $(COMPOSE_ENV) down

dev-logs:
	podman-compose $(COMPOSE_ENV) logs -f

vapid-keys: dev-image
	$(GO_RUN) go run ./cmd/vapid

apk:
	$(FLUTTER_RUN) '$(FLUTTER_PREP) && flutter build apk --debug --dart-define=API_BASE_URL=$${API_BASE_URL:-http://10.0.2.2:8787} --dart-define=WORKOS_CLIENT_ID=$${WORKOS_CLIENT_ID:-$(WORKOS_CLIENT_ID_DEFAULT)}'

# Browser tryout: same-origin cookie AuthKit via Caddy at http://localhost:8787/
# --no-web-resources-cdn: ship CanvasKit in the bundle (Caddy CSP blocks Google CDN).
web:
	$(FLUTTER_RUN) '$(FLUTTER_PREP) && flutter build web --release --base-href=/ --no-web-resources-cdn --dart-define=WORKOS_CLIENT_ID=$${WORKOS_CLIENT_ID:-$(WORKOS_CLIENT_ID_DEFAULT)}'
