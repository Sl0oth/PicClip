#!/bin/bash
# One-time, free: creates a self-signed code-signing certificate "PicClip Self-Signed" in your login keychain.
# Why: macOS remembers an app's permissions per signature, and the updater only accepts updates signed by the
# same certificate. Ad-hoc signing changes every build, so neither works without this.
# Back up the certificate (Keychain Access → export) — releases signed with a new one won't auto-update old installs.
set -euo pipefail
NAME="PicClip Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -p codesigning | grep -q "$NAME"; then echo "'$NAME' already exists."; exit 0; fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
# /usr/bin/openssl (LibreSSL) writes a .p12 that the macOS keychain can import.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/cert.p12" -passout pass:picclip
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P picclip -T /usr/bin/codesign
# Let codesign use the key without a keychain popup on every build.
read -r -s -p "Your Mac login password (lets codesign use the key without asking each build): " PW; echo
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KEYCHAIN" >/dev/null
unset PW
echo "Trusting it for code signing (macOS will ask for your password)…"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
echo "Done. ./build.sh will now sign with '$NAME'."
