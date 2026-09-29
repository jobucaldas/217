FROM docker.io/golang:1.25-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/go/bin:/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.88.0 && \
    rustup target add wasm32-unknown-unknown --toolchain 1.88.0 && \
    cargo +1.88.0 install wasm-bindgen-cli --version 0.2.121 --locked

RUN mkdir -p /workspace
WORKDIR /workspace
