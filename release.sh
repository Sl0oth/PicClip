#!/bin/bash
# Usage: ./release.sh 0.2.0 ["What changed"]   (notes default to "Bug fixes and improvements.")
# Bumps the version, builds a universal app, zips it, commits + tags, pushes, and publishes a GitHub release.
# Installed copies pick it up automatically (Check for Updates… or within a day).
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:?usage: ./release.sh <version> [notes]}"; VERSION="${VERSION#v}"
PLIST=Resources/Info.plist

[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first."; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "v$VERSION already exists."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run: gh auth login"; exit 1; }
[[ "$(gh repo view --json visibility -q .visibility)" == "PUBLIC" ]] \
    || echo "warning: the repo is private — installed apps can't see this release until it's public."
security find-identity -p codesigning 2>/dev/null | grep -q "PicClip Self-Signed" \
    || echo "warning: no 'PicClip Self-Signed' cert (scripts/make-signing-cert.sh) — users will re-grant permissions after updating."

BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" -c "Set CFBundleVersion $BUILD" "$PLIST"

UNIVERSAL=1 ./build.sh
rm -f build/PicClip.zip
ditto -c -k --keepParent build/PicClip.app build/PicClip.zip

git commit -qam "Release $VERSION"
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"
# Change notes first (shown in the in-app update alert), then first-install help (hidden there via the marker).
NOTES="${2:-Bug fixes and improvements.}

<!-- install -->
---
### New to PicClip? One-time setup
**Easiest:** paste this into Terminal. It installs PicClip into Applications and opens it, with no security warning:
\`\`\`sh
curl -fsSL https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/latest/download/PicClip.zip -o /tmp/PicClip.zip && ditto -xk /tmp/PicClip.zip /Applications && open /Applications/PicClip.app
\`\`\`
**Or download PicClip.zip below:** unzip it, drag PicClip into Applications, and open it. macOS will say it can't verify the app (PicClip is free and isn't paid-notarized by Apple). Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway**. You only do this once. Updates install themselves after that."
gh release create "v$VERSION" build/PicClip.zip --title "PicClip $VERSION" --notes "$NOTES"
echo "Released PicClip $VERSION"
