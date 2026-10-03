#!/usr/bin/env bash
# Wraps the `flutter build linux --release` bundle in an AppImage.
# Usage: build-appimage.sh [bundle-dir] [output.AppImage]
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
frontend="$(cd "$here/../.." && pwd)"
bundle="${1:-$frontend/build/linux/x64/release/bundle}"
out="${2:-$frontend/build/217-x86_64.AppImage}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

appdir="$work/217.AppDir"
mkdir -p "$appdir/usr/bin"
cp -a "$bundle/." "$appdir/usr/bin/"
cp "$here/a217.desktop" "$appdir/a217.desktop"
cp "$frontend/linux/runner/icon.png" "$appdir/a217.png"
ln -s usr/bin/a217 "$appdir/AppRun"

tool="${APPIMAGETOOL:-$work/appimagetool}"
if [ ! -x "$tool" ]; then
  curl -fsSL -o "$tool" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$tool"
fi

mkdir -p "$(dirname "$out")"
# Extract-and-run: CI runners and containers have no FUSE.
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream "$appdir" "$out"
