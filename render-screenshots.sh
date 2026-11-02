#!/usr/bin/env sh
# Regenerates the store-listing screenshots in assets/*-screenshots/.
#
# Renders the app's real screens with sample data (frontend/tool/store_screenshots_test.dart).
# Uses the Flutter on PATH when there is one (CI); otherwise runs itself inside the
# Flutter image with podman or docker, so nothing is installed on the host.
#
#   ./render-screenshots.sh
#   FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:3.27.1 ./render-screenshots.sh
set -eu
cd "$(dirname "$0")"

if command -v flutter >/dev/null 2>&1; then
  git config --global --add safe.directory /sdks/flutter 2>/dev/null || true
  cd frontend
  flutter pub get
  flutter test tool/store_screenshots_test.dart --update-goldens
  exit 0
fi

engine="$(command -v podman || command -v docker || true)"
if [ -z "$engine" ]; then
  echo "render-screenshots.sh: needs flutter, podman or docker on PATH" >&2
  exit 1
fi
exec "$engine" run --rm -v "$PWD:/workspace:Z" -w /workspace \
  "${FLUTTER_IMAGE:-ghcr.io/cirruslabs/flutter:stable}" ./render-screenshots.sh
