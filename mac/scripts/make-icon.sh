#!/bin/bash
# Resources/icon/AppIcon.svg から Resources/AppIcon.icns を作る(rsvg-convert が要る)
set -euo pipefail

cd "$(dirname "$0")/.."
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" Resources/icon/AppIcon.svg -o "$iconset/icon_${size}x${size}.png"
    rsvg-convert -w "$((size * 2))" -h "$((size * 2))" Resources/icon/AppIcon.svg -o "$iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
echo Resources/AppIcon.icns
