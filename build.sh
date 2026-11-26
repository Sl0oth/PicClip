#!/bin/bash
# Usage: ./build.sh [run]   (override signing with SIGN_ID=...)
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/PicClip.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/PicClip" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns Resources/Icon/MenuBarIcon.svg "$APP/Contents/Resources/"
# Stable signature (Apple Development cert if present) so macOS remembers folder permissions across rebuilds.
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
codesign --force --sign "${SIGN_ID:--}" "$APP" 2>/dev/null || {
    echo "warning: signing with '$SIGN_ID' failed (keychain locked?) — using ad-hoc signature"
    codesign --force --sign - "$APP"
}
echo "Built $APP"
if [[ "${1:-}" == "run" ]]; then
    pkill -x PicClip 2>/dev/null && sleep 0.5 || true
    open "$APP"
fi
