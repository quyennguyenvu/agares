#!/bin/bash
# One-time: creates the self-signed "Agares Dev" code-signing certificate in the login keychain.
set -euo pipefail

NAME="Agares Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Certificate \"$NAME\" already exists."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.conf" <<EOF
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
EOF

# /usr/bin/openssl is LibreSSL, whose PKCS#12 output the security tool can read.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$TMP/cert.conf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/identity.p12" -passout pass:agares
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P agares -T /usr/bin/codesign

echo "Created \"$NAME\"."
