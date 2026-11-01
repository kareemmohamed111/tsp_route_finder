#!/usr/bin/env bash
# Regenerates doc/images/before_after.png and doc/images/delivery.png from
# real solver output. Requires Google Chrome and ImageMagick (magick).
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

dart run tool/readme_assets.dart "$WORK"
mkdir -p doc/images

shot() { # svg png width height
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=2 --window-size="$3,$4" \
    --screenshot="$2" "file://$1" >/dev/null 2>&1
  magick "$2" -strip +dither -colors 256 "PNG8:$2"
}

shot "$WORK/before_after.svg" doc/images/before_after.png 1200 770
shot "$WORK/delivery.svg" doc/images/delivery.png 1200 700
ls -lh doc/images
