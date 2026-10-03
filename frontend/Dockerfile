# Flutter web release bundle (static files in /app/dist, served by Caddy).
# Build context: frontend/ after `make mobile-web` (mobile/build/web).
FROM docker.io/library/alpine:3.20
RUN adduser -D -H -u 65532 -g nonroot nonroot
COPY mobile/build/web/ /app/dist/
USER 65532:65532
