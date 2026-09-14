#!/usr/bin/env bash
set -euo pipefail

ROOT="${ANDROID_REPO_ROOT:-$(pwd)}"
ARTIFACT_DIR="${ANDROID_ARTIFACT_DIR:-$ROOT/artifacts/android}"
TMP_HOME="${ANDROID_USER_HOME:-/tmp/217-android-home}"
ANDROID_HOME="${HOME:-$TMP_HOME}"
AVD_HOME="${ANDROID_AVD_HOME:-/tmp/217-android-avd}"
AVD_NAME="${ANDROID_AVD_NAME:-217-playstore}"
SYSTEM_IMAGE="${ANDROID_SYSTEM_IMAGE:-system-images;android-34-ext12;google_apis_playstore;x86_64}"
HOST_PORT="${ANDROID_HOST_PORT:-8080}"
HOST_SERVICE_PORT="${ANDROID_HOST_SERVICE_PORT:-$HOST_PORT}"
CDP_PORT="${ANDROID_CDP_PORT:-9222}"
CHROME_PACKAGE="${ANDROID_CHROME_PACKAGE:-com.android.chrome}"
PIDFILE="$ARTIFACT_DIR/emulator.pid"

log() {
  printf '[android] %s\n' "$*"
}

ensure_dirs() {
  mkdir -p "$ARTIFACT_DIR" "$TMP_HOME" "$AVD_HOME"
  mkdir -p "$ANDROID_HOME/.android"
}

sdk_root() {
  printf '%s\n' "${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
}

emulator_bin() {
  local sdk
  sdk="$(sdk_root)"
  printf '%s\n' "$sdk/emulator/emulator"
}

adb_bin() {
  local sdk
  sdk="$(sdk_root)"
  printf '%s\n' "$sdk/platform-tools/adb"
}

avdmanager_bin() {
  local sdk candidate
  sdk="$(sdk_root)"
  for candidate in "$sdk"/cmdline-tools/*/bin/avdmanager; do
    [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  printf '%s\n' "$sdk/cmdline-tools/latest/bin/avdmanager"
}

run_adb() {
  "$(adb_bin)" "$@"
}

adb_vendor_keys_dir() {
  printf '%s\n' "$ANDROID_HOME/.android"
}

ensure_adb_keys() {
  local key_dir key_file
  key_dir="$(adb_vendor_keys_dir)"
  key_file="$key_dir/adbkey"
  if [ ! -f "$key_file" ]; then
    umask 077
    "$(adb_bin)" keygen "$key_file"
  fi
  chmod 600 "$key_file" "$key_file.pub" 2>/dev/null || true
  export ADB_VENDOR_KEYS="$key_dir"
}

record_adb_auth_checkpoint() {
  local key_dir key_file key_pub fingerprint
  key_dir="$(adb_vendor_keys_dir)"
  key_file="$key_dir/adbkey"
  key_pub="$key_file.pub"
  fingerprint="$(sha256sum "$key_pub" 2>/dev/null | awk '{print $1}' || true)"
  jq -n \
    --arg key_dir "$key_dir" \
    --arg key_file "$key_file" \
    --arg key_pub "$key_pub" \
    --arg fingerprint "$fingerprint" \
    --arg emulator_bin "$(emulator_bin)" \
    --arg adb_vendor_keys "${ADB_VENDOR_KEYS:-}" \
    --arg adb_state "$(run_adb get-state 2>&1 || true)" \
    '{key_dir: $key_dir, key_file: $key_file, key_pub: $key_pub, fingerprint: $fingerprint, emulator_bin: $emulator_bin, adb_vendor_keys: $adb_vendor_keys, adb_state: $adb_state}' > "$ARTIFACT_DIR/adb-auth-checkpoint.json"
}

adb_wait_state() {
  local deadline state
  deadline=$(( $(date +%s) + ${ANDROID_ADB_STATE_TIMEOUT:-180} ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    state="$(run_adb get-state 2>/dev/null || true)"
    [ "$state" = "device" ] && return 0
    sleep 5
  done
  log "adb did not reach device state"
  return 1
}

kill_stale_adb_server() {
  local adb
  adb="$(adb_bin)"
  "$adb" kill-server >/dev/null 2>&1 || true
}

validate_sdk_layout() {
  local sdk platforms_dir system_image_dir
  sdk="$(sdk_root)"
  platforms_dir="$sdk/platforms/android-34"
  system_image_dir="$sdk/$(printf '%s' "$SYSTEM_IMAGE" | tr ';' '/')"
  [ -d "$sdk" ] || { log "missing ANDROID_SDK_ROOT: $sdk"; exit 70; }
  [ -d "$platforms_dir" ] || { log "missing platforms dir: $platforms_dir"; exit 70; }
  [ -d "$system_image_dir" ] || { log "missing system image dir: $system_image_dir"; exit 70; }
}

record_environment() {
  local sdk version chrome_version chrome_packages
  sdk="$(sdk_root)"
  version="$(run_adb shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
  chrome_packages="$(run_adb shell pm list packages 2>/dev/null | grep -E '^package:com\\.android\\.chrome$' || true)"
  chrome_version="$(run_adb shell dumpsys package "$CHROME_PACKAGE" 2>/dev/null | grep -m1 'versionName=' | sed 's/.*versionName=//' | tr -d '\r' || true)"
  jq -n \
    --arg root "$ROOT" \
    --arg sdkroot "$sdk" \
    --arg avd "$AVD_NAME" \
    --arg system_image "$SYSTEM_IMAGE" \
    --arg host_port "$HOST_PORT" \
    --arg cdp_port "$CDP_PORT" \
    --arg chrome_package "$CHROME_PACKAGE" \
    --arg chrome_version "$chrome_version" \
    --arg chrome_packages "$chrome_packages" \
    --arg sdk_api "$version" \
    '{
      root: $root,
      sdk_root: $sdkroot,
      avd_name: $avd,
      system_image: $system_image,
      host_port: ($host_port | tonumber),
      cdp_port: ($cdp_port | tonumber),
      chrome_package: $chrome_package,
      chrome_version: $chrome_version,
      chrome_packages: $chrome_packages,
      android_api: ($sdk_api | tonumber)
    }' > "$ARTIFACT_DIR/environment.json"
}

create_avd() {
  if [ -d "$AVD_HOME/$AVD_NAME.avd" ]; then
    return 0
  fi
  validate_sdk_layout
  log "creating AVD $AVD_NAME"
  { printf 'no\n'; } | "$(avdmanager_bin)" create avd --force -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -d pixel_7
}

start_emulator() {
  create_avd
  log "starting emulator"
  "$(emulator_bin)" -avd "$AVD_NAME" \
    -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data \
    -gpu swiftshader_indirect -accel on -skip-adb-auth -memory 4096 -cores 4 \
    >"$ARTIFACT_DIR/emulator.log" 2>&1 &
  echo $! > "$PIDFILE"
}

wait_boot() {
  log "waiting for emulator boot"
  kill_stale_adb_server
  ensure_adb_keys
  run_adb start-server >/dev/null 2>&1 || true
  run_adb wait-for-device
  if ! adb_wait_state; then
    record_adb_auth_checkpoint
    return 1
  fi
  until [ "$(run_adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 5
  done
  run_adb shell input keyevent 82 >/dev/null 2>&1 || true
}

configure_ports() {
  log "configuring adb reverse/forward"
  run_adb reverse tcp:"$HOST_PORT" tcp:"$HOST_SERVICE_PORT" >/dev/null 2>&1 || true
  run_adb forward tcp:"$CDP_PORT" localabstract:chrome_devtools_remote >/dev/null 2>&1 || true
}

write_chrome_command_line() {
  log "writing Chrome command line flags"
  run_adb shell am force-stop "$CHROME_PACKAGE" >/dev/null 2>&1 || true
  run_adb shell sh -c "echo 'chrome --no-first-run --no-default-browser-check --disable-fre --disable-background-networking --disable-sync --disable-component-update --remote-debugging-port=${CDP_PORT}' > /data/local/tmp/chrome-command-line"
  run_adb shell chmod 644 /data/local/tmp/chrome-command-line >/dev/null 2>&1 || true
}

grant_notification_permission() {
  run_adb shell pm grant "$CHROME_PACKAGE" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  run_adb shell cmd appops set "$CHROME_PACKAGE" POST_NOTIFICATION allow >/dev/null 2>&1 || \
    run_adb shell appops set "$CHROME_PACKAGE" POST_NOTIFICATION allow >/dev/null 2>&1 || true
}

launch_chrome() {
  log "launching Chrome"
  run_adb shell am start -n "$CHROME_PACKAGE/com.google.android.apps.chrome.Main" \
    -a android.intent.action.VIEW \
    -d "http://localhost:${HOST_PORT}" \
    --ez com.android.browser.application_id "$CHROME_PACKAGE" \
    --ez create_new_tab true \
    --ez org.chromium.chrome.browser.device_dialog.disable true \
    >/dev/null 2>&1 || \
  run_adb shell monkey -p "$CHROME_PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
}

cleanup() {
  local pid
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    log "stopping emulator $pid"
    run_adb emu kill >/dev/null 2>&1 || true
    sleep 5
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$TMP_HOME" "$AVD_HOME"
  rm -f "$PIDFILE"
}

run_start() {
  ensure_dirs
  validate_sdk_layout
  ensure_adb_keys
  kill_stale_adb_server
  trap cleanup EXIT INT TERM
  start_emulator
  wait_boot
  configure_ports
  write_chrome_command_line
  grant_notification_permission
  launch_chrome
  record_environment
  log "emulator ready; leaving Chrome and the emulator running"
  while true; do
    sleep 60
  done
}

run_validate() {
  ensure_dirs
  validate_sdk_layout
  ensure_adb_keys
  kill_stale_adb_server
  trap cleanup EXIT INT TERM
  start_emulator
  wait_boot
  configure_ports
  write_chrome_command_line
  grant_notification_permission
  launch_chrome
  record_environment
  node "$ROOT/dev/android-emulator/scripts/validate.cjs"
}

case "${1:-validate}" in
  start)
    shift || true
    run_start "$@"
    ;;
  validate)
    shift || true
    run_validate "$@"
    ;;
  cleanup)
    cleanup
    ;;
  *)
    printf 'Usage: %s {start|validate|cleanup}\n' "$0" >&2
    exit 64
    ;;
esac
