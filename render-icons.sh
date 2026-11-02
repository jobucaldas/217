#!/usr/bin/env sh
# Renders every icon from the SVG sources in assets/branding/, the only place to edit them:
#
#   frontend/android/.../mipmap-*/ic_launcher.png      Android launcher
#   frontend/web/icons/*, favicon.svg, favicon.png     web app and manifest
#   frontend/linux/runner/icon.png                     Linux (AppImage)
#   frontend/windows/runner/resources/app_icon.ico     Windows (exe, installer)
#   assets/app-icon/*, assets/feature-graphic/*        Google Play listing
#
# The platform copies stay committed under frontend/ because each platform's build (and the
# frontend Docker context) reads them from there. Uses ImageMagick on PATH when there is
# one; otherwise runs itself in an Alpine container with podman or docker.
#
#   ./render-icons.sh            render and overwrite
#   ./render-icons.sh --check    render to a temp folder and fail if a committed icon no
#                                longer matches its source (CI runs this)
set -eu
cd "$(dirname "$0")"

if ! command -v magick >/dev/null 2>&1; then
  engine="$(command -v podman || command -v docker || true)"
  if [ -z "$engine" ]; then
    echo "render-icons.sh: needs ImageMagick, podman or docker on PATH" >&2
    exit 1
  fi
  exec "$engine" run --rm -v "$PWD:/workspace:Z" -w /workspace docker.io/library/alpine:3 \
    sh -c 'apk add --no-cache imagemagick imagemagick-svg >/dev/null && ./render-icons.sh "$@"' sh "$@"
fi

out=.
if [ "${1:-}" = "--check" ]; then
  out="$(mktemp -d)"
  trap 'rm -rf "$out"' EXIT
fi

src=assets/branding
fe=$out/frontend
play=$out/assets

# png <svg> <size> <out> [format]
png() {
  mkdir -p "$(dirname "$3")"
  magick -background none -density 384 "$1" -resize "${2}x${2}" -strip "${4:-PNG24}:$3"
}

for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  png "$src/app-icon.svg" "${d#*:}" "$fe/android/app/src/main/res/mipmap-${d%:*}/ic_launcher.png"
done

for s in 192 512; do
  png "$src/app-icon.svg" "$s" "$fe/web/icons/Icon-$s.png"
  png "$src/app-icon-maskable.svg" "$s" "$fe/web/icons/Icon-maskable-$s.png"
done
mkdir -p "$fe/web"
cp "$src/favicon.svg" "$fe/web/favicon.svg"
# The PNG favicon is the wordmark in the brand red (the SVG one follows the color scheme).
sed 's/#1A1A1A/#F43F5E/' "$src/favicon.svg" > /tmp/favicon-red.svg
png /tmp/favicon-red.svg 64 "$fe/web/favicon.png" PNG32
rm -f /tmp/favicon-red.svg

png "$src/app-icon.svg" 512 "$fe/linux/runner/icon.png"
mkdir -p "$fe/windows/runner/resources"
magick -background none -density 384 "$src/app-icon.svg" \
  -define icon:auto-resize=256,128,64,48,32,24,16 "$fe/windows/runner/resources/app_icon.ico"

png "$src/app-icon.svg" 512 "$play/app-icon/app-icon-512.png"
png "$src/app-icon.svg" 1024 "$play/app-icon/app-icon-1024.png"
mkdir -p "$play/feature-graphic"
magick -background none -density 192 "$src/feature-graphic.svg" -resize 1024x500! -strip \
  "PNG24:$play/feature-graphic/feature-graphic-1024x500.png"

# --check: every rendered file must match the committed one. Pixels are compared with a
# tolerance (another ImageMagick or librsvg build anti-aliases a little differently), so
# only a real change to a source, or a stale icon, fails.
[ "$out" = . ] && exit 0
status=0
for f in $(cd "$out" && find . -type f | sort); do
  if [ ! -f "$f" ]; then
    echo "missing: $f (run ./render-icons.sh)"; status=1; continue
  fi
  case "$f" in
    *.svg) cmp -s "$out/$f" "$f" && continue ;;
    *) # -append stacks the frames of an .ico; same-size PNGs are one frame
      magick "$out/$f" -background none -append /tmp/a.miff
      magick "$f" -background none -append /tmp/b.miff
      diff_px="$(magick compare -fuzz 5% -metric AE /tmp/a.miff /tmp/b.miff null: 2>&1 || true)"
      [ "${diff_px%% *}" = 0 ] && continue ;;
  esac
  echo "out of date: $f (run ./render-icons.sh and commit)"; status=1
done
exit "$status"
