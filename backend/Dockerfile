FROM docker.io/golang:1.25-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
CMD ["go", "run", "./cmd/server"]
