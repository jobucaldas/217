DEV_IMAGE ?= localhost/217-dev
FLUTTER_IMAGE ?= ghcr.io/cirruslabs/flutter:stable
PODMAN_RUN = podman run --rm -v "$(CURDIR):/workspace:Z" -w /workspace $(DEV_IMAGE)
FLUTTER_RUN = podman run --rm -v "$(CURDIR):/workspace:Z" -w /workspace/mobile $(FLUTTER_IMAGE) bash -lc
COMPOSE_ENV = $(if $(wildcard .env.reminders.local),--env-file .env.reminders.local,) $(if $(wildcard .env.local),--env-file .env.local,)

.PHONY: dev-image test-backend test-mobile test validate dev-up dev-down dev-logs vapid-keys mobile-apk mobile-web

dev-image:
	podman build -t $(DEV_IMAGE) -f .devcontainer/Dockerfile .

test-backend: dev-image
	$(PODMAN_RUN) sh -c 'cd backend && test -z "$$(gofmt -l .)" && go test -mod=readonly ./... -v && go vet -mod=readonly ./... && go build -mod=readonly ./...'

test-mobile:
	$(FLUTTER_RUN) 'git config --global --add safe.directory /sdks/flutter >/dev/null 2>&1 || true; flutter pub get && flutter analyze && flutter test'

test: test-backend test-mobile

validate: test

dev-up: dev-image
	podman-compose $(COMPOSE_ENV) up -d --build

dev-down:
	podman-compose $(COMPOSE_ENV) down

dev-logs:
	podman-compose $(COMPOSE_ENV) logs -f

vapid-keys: dev-image
	$(PODMAN_RUN) sh -c 'cd backend && go run ./cmd/vapid'

mobile-apk:
	$(FLUTTER_RUN) 'git config --global --add safe.directory /sdks/flutter >/dev/null 2>&1 || true; flutter pub get && flutter build apk --debug --dart-define=API_BASE_URL=$${API_BASE_URL:-http://10.0.2.2:8787} --dart-define=WORKOS_CLIENT_ID=$${WORKOS_CLIENT_ID:-client_01M3QCMK75B35RPC8EAJA5GREP}'

# Browser tryout: same-origin cookie AuthKit via Caddy at http://localhost:8787/
mobile-web:
	mkdir -p mobile/build/web
	$(FLUTTER_RUN) 'git config --global --add safe.directory /sdks/flutter >/dev/null 2>&1 || true; flutter pub get && flutter build web --release --base-href=/ --dart-define=WORKOS_CLIENT_ID=$${WORKOS_CLIENT_ID:-client_01M3QCMK75B35RPC8EAJA5GREP}'
