#!/bin/bash
# Usage: ./build.sh [run]
#   UNIVERSAL=1  build for Apple Silicon + Intel (release.sh sets this)
#   SIGN_ID=...  override the signing identity
set -euo pipefail
cd "$(dirname "$0")"
ARCHS=(); [[ "${UNIVERSAL:-}" == 1 ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
APP=build/PicClip.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/PicClip" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns Resources/Icon/MenuBarIcon.svg "$APP/Contents/Resources/"
# Stable signature = macOS keeps PicClip's permissions across updates. Make one once with scripts/make-signing-cert.sh.
if [[ -z "${SIGN_ID:-}" ]] && security find-identity -p codesigning 2>/dev/null | grep -q "PicClip Self-Signed"; then
    SIGN_ID="PicClip Self-Signed"
fi
if ! codesign --force --sign "${SIGN_ID:--}" "$APP" 2>/dev/null; then
    echo "warning: couldn't sign with '${SIGN_ID:-}' — using an ad-hoc signature"
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
if [[ "${1:-}" == "run" ]]; then
    pkill -x PicClip 2>/dev/null && sleep 0.5 || true
    open "$APP"
fi
