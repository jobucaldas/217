DEV_IMAGE ?= localhost/217-dev
PODMAN_RUN = podman run --rm -v "$(CURDIR):/workspace:Z" -w /workspace $(DEV_IMAGE)
COMPOSE_ENV = $(if $(wildcard .env.reminders.local),--env-file .env.reminders.local,) $(if $(wildcard .env.local),--env-file .env.local,)

.PHONY: dev-image frontend-dist test-backend test-frontend test validate dev-up dev-down dev-logs vapid-keys

dev-image:
	podman build -t $(DEV_IMAGE) -f .devcontainer/Dockerfile .

frontend-dist: dev-image
	$(PODMAN_RUN) sh -c 'cd frontend && ./build.sh'

test-backend: dev-image
	$(PODMAN_RUN) sh -c 'cd backend && test -z "$$(gofmt -l .)" && go test -mod=readonly ./... -v && go vet -mod=readonly ./... && go build -mod=readonly ./...'

test-frontend: dev-image
	$(PODMAN_RUN) sh -c 'cd frontend && cargo fmt -- --check && cargo test --locked && cargo clippy --locked --all-targets -- -D warnings'

test: test-backend test-frontend

validate: test frontend-dist

dev-up: frontend-dist
	podman-compose $(COMPOSE_ENV) up -d --build

dev-down:
	podman-compose $(COMPOSE_ENV) down

dev-logs:
	podman-compose $(COMPOSE_ENV) logs -f

vapid-keys: dev-image
	$(PODMAN_RUN) sh -c 'cd backend && go run ./cmd/vapid'
