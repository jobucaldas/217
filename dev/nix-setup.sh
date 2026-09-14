#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Run only inside `nix develop path:.`; install into this workspace, never globally.
cargo install --locked --version 0.2.121 --root "$PWD/.dev-tools" wasm-bindgen-cli
npm --prefix e2e ci --ignore-scripts
