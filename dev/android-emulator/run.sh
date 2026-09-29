#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
MODE="${1:-validate}"
shift || true
IMAGE="${ANDROID_NIX_IMAGE:-docker.io/nixos/nix:2.34.8}"
NIX_CONFIG="experimental-features = nix-command flakes
accept-flake-config = true"
NIX_VOLUME="${ANDROID_NIX_VOLUME:-android-nix-store}"
HOST_PORT="${ANDROID_HOST_PORT:-18080}"
DEVICE_PORT="${ANDROID_DEVICE_PORT:-8080}"
CADDY_NAME="${ANDROID_CADDY_NAME:-217-android-caddy}"
CADDY_NETWORK="${ANDROID_CADDY_NETWORK:-217-validation_default}"

case "$MODE" in
  cleanup|cleanup-volume)
    podman volume rm -f "$NIX_VOLUME"
    exit 0
    ;;
esac

podman volume inspect "$NIX_VOLUME" >/dev/null 2>&1 || podman volume create "$NIX_VOLUME" >/dev/null

# Serve the built app on a host-only port; Android reaches it via adb reverse.
podman rm -f "$CADDY_NAME" >/dev/null 2>&1 || true
podman run -d --name "$CADDY_NAME" --network "$CADDY_NETWORK" -p "$HOST_PORT:8080" \
  -v "$ROOT/frontend/dist:/srv/frontend:ro,Z" -v "$ROOT/Caddyfile:/etc/caddy/Caddyfile:ro,Z" \
  docker.io/library/caddy:2-alpine >/dev/null
cleanup_caddy() { podman rm -f "$CADDY_NAME" >/dev/null 2>&1 || true; }
trap cleanup_caddy EXIT
until curl -fsS "http://localhost:$HOST_PORT/pwa.js" | grep -q 'window.pwa217'; do sleep 1; done
curl -fsS "http://localhost:$HOST_PORT/manifest.json" >/dev/null

exec podman run --rm \
  --device /dev/kvm \
  --network host \
  -v "$NIX_VOLUME:/nix:rw,exec" \
  --tmpfs /tmp:rw,exec,size=${ANDROID_TMPFS_SIZE:-8g} \
  -e HOME="${ANDROID_USER_HOME:-/tmp/217-android-home}" \
  -e ADB_VENDOR_KEYS="${ANDROID_USER_HOME:-/tmp/217-android-home}/.android" \
  -e ANDROID_REPO_ROOT="$ROOT" \
  -e ANDROID_ARTIFACT_DIR="$ROOT/artifacts/android" \
  -e ANDROID_HOST_PORT="$DEVICE_PORT" \
  -e ANDROID_HOST_SERVICE_PORT="$HOST_PORT" \
  -e ANDROID_CDP_PORT="${ANDROID_CDP_PORT:-9222}" \
  -e ANDROID_CHROME_PACKAGE="${ANDROID_CHROME_PACKAGE:-com.android.chrome}" \
  -e ANDROID_SYSTEM_IMAGE="${ANDROID_SYSTEM_IMAGE:-system-images;android-34-ext12;google_apis_playstore;x86_64}" \
  -e ANDROID_AVD_NAME="${ANDROID_AVD_NAME:-217-playstore}" \
  -e ANDROID_USER_HOME="${ANDROID_USER_HOME:-/tmp/217-android-home}" \
  -e ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-/tmp/217-android-avd}" \
  -e NIX_CONFIG="$NIX_CONFIG" \
  -v "$ROOT:$ROOT:Z" \
  -w "$ROOT/dev/android-emulator" \
  "$IMAGE" \
  nix --extra-experimental-features 'nix-command flakes' run "path:$ROOT/dev/android-emulator" -- "$MODE" "$@"
