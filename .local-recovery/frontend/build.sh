#!/bin/sh
set -eu
cd "$(dirname "$0")"

printf '%s\n' 'Building frontend WASM...'
cargo build --locked --target wasm32-unknown-unknown --release

printf '%s\n' 'Generating browser bindings and complete PWA shell...'
rm -rf dist.next
mkdir -p dist.next
wasm-bindgen --out-dir dist.next --target web "${CARGO_TARGET_DIR:-target}/wasm32-unknown-unknown/release/app_217.wasm"
cp index.html dist.next/index.html
cp static/manifest.webmanifest static/pwa.js static/service-worker.js static/icon-192.png static/icon-512.png static/google-signin.png dist.next/
rm -rf dist
mv dist.next dist

test -s dist/index.html
test -s dist/app_217.js
test -s dist/app_217_bg.wasm
test -s dist/manifest.webmanifest
test -s dist/service-worker.js
test -s dist/pwa.js
test -s dist/icon-192.png
test -s dist/icon-512.png
test -s dist/google-signin.png
printf '%s\n' 'Frontend build complete: dist/'
