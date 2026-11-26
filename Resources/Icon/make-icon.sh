#!/bin/bash
# Regenerates Resources/AppIcon.icns from AppIcon.svg. Run after editing the SVG.
set -euo pipefail
cd "$(dirname "$0")"
TMP=$(mktemp -d)
swiftc -O -o "$TMP/render" render.swift
ICONSET="$TMP/AppIcon.iconset"; mkdir "$ICONSET"
for s in 16 32 128 256 512; do
    "$TMP/render" AppIcon.svg "$ICONSET/icon_${s}x${s}.png" $s
    "$TMP/render" AppIcon.svg "$ICONSET/icon_${s}x${s}@2x.png" $((s * 2))
done
iconutil -c icns "$ICONSET" -o ../AppIcon.icns
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns"
