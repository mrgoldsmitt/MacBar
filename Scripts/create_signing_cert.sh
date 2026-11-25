#!/bin/bash
#
# Creates a stable 10-year local Code Signing certificate ("MacBar Local Code Signing")
# in ~/Library/Keychains/login.keychain-db so local MacBar builds keep a fixed
# certificate leaf requirement across rebuilds instead of changing ad-hoc cdhashes.
#
set -euo pipefail

CERT_NAME="${CERT_NAME:-MacBar Local Code Signing}"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

existing_hash="$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
    | sed -n "s/.* \([0-9A-F]\{40\}\) \"${CERT_NAME}\".*/\1/p" | head -n 1 || true)"

if [ -n "$existing_hash" ]; then
    echo "Existing code-signing identity found: $existing_hash ($CERT_NAME)"
    exit 0
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_DIR/openssl.cnf" <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
x509_extensions    = v3_codesign
prompt             = no

[ req_distinguished_name ]
CN = ${CERT_NAME}
O  = mrgoldsmitt
C  = DE

[ v3_codesign ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP_DIR/key.pem" \
    -out "$TMP_DIR/cert.pem" \
    -days 3650 \
    -sha256 \
    -config "$TMP_DIR/openssl.cnf" \
    2>/dev/null

P12_PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export \
    -out "$TMP_DIR/cert.p12" \
    -inkey "$TMP_DIR/key.pem" \
    -in "$TMP_DIR/cert.pem" \
    -name "$CERT_NAME" \
    -passout "pass:$P12_PASS"

security import "$TMP_DIR/cert.p12" \
    -k "$KEYCHAIN" \
    -P "$P12_PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null

new_hash="$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
    | sed -n "s/.* \([0-9A-F]\{40\}\) \"${CERT_NAME}\".*/\1/p" | head -n 1 || true)"

if [ -z "$new_hash" ]; then
    echo "error: failed to register $CERT_NAME in $KEYCHAIN" >&2
    exit 1
fi

echo "Created local code-signing identity: $new_hash ($CERT_NAME)"
