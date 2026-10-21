#!/usr/bin/env bash
# Renders the app icon variants in design/icon/ into the asset catalog. The PNGs are checked in, so
# this only needs running after editing an SVG. Requires rsvg-convert (brew install librsvg).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$root/design/icon"
icon_set="$root/Mothball/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null; then
  echo "rsvg-convert not found; install it with: brew install librsvg" >&2
  exit 1
fi

for variant in AppIcon AppIcon-Dark AppIcon-Tinted; do
  rsvg-convert --width 1024 --height 1024 "$source_dir/$variant.svg" \
    --output "$icon_set/$variant.png"
  echo "rendered $variant.png"
done

# App Store validation rejects a primary icon with an alpha channel.
if [[ "$(sips -g hasAlpha "$icon_set/AppIcon.png" | awk '/hasAlpha/ { print $2 }')" != "no" ]]; then
  echo "AppIcon.png has an alpha channel; give AppIcon.svg an opaque background" >&2
  exit 1
fi
