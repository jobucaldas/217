# `dev` stage: Go toolchain for compose (`go run`) and `docker compose run --rm test-backend`.
# Default (last) stage: production API image published to GHCR by CI.
FROM docker.io/golang:1.26-bookworm AS dev
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
CMD ["go", "run", "./cmd/server"]

FROM docker.io/golang:1.26-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

FROM docker.io/library/alpine:3.20
# Its own uid (not the web image's 65532), so only the API can read its TLS key.
RUN apk add --no-cache ca-certificates \
	&& adduser -D -H -u 10001 -g api api
COPY --from=build /out/server /usr/local/bin/server
USER 10001:10001
EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/server"]
CMD ["-addr", ":3000"]
