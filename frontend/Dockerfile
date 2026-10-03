# syntax=docker/dockerfile:1
# The web app: a Flutter web bundle in /app/dist, served by Caddy, which also
# proxies /api/* to the backend. One image, nothing to mount.
#
# Stages (pick one with --target):
#   local     builds the bundle from this checkout (docker-compose.yml uses it)
#   prebuilt  copies an existing build/web (CI builds it once and publishes this; default)

ARG FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:stable
FROM ${FLUTTER_IMAGE} AS web-build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
COPY packages packages
RUN git config --global --add safe.directory /sdks/flutter && flutter pub get
COPY . .
RUN flutter build web --release --no-web-resources-cdn --pwa-strategy=none

FROM docker.io/library/caddy:alpine AS runtime
RUN adduser -D -H -u 65532 -g nonroot nonroot \
    && mkdir -p /app/dist /data /config \
    && chown -R 65532:65532 /data /config
COPY Caddyfile /etc/caddy/Caddyfile
USER 65532:65532
EXPOSE 8787

FROM runtime AS local
COPY --from=web-build /app/build/web/ /app/dist/

FROM runtime AS prebuilt
COPY build/web/ /app/dist/
