#!/usr/bin/env bash
# Creates a local LAB-ONLY Authenticode certificate for signing NeoOptimize builds.
# This does not create Microsoft SmartScreen reputation. Use an OV/EV certificate
# from a trusted CA for production releases.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CERT_DIR="$ROOT_DIR/certs"
PASS_FILE="$CERT_DIR/lab-codesign.pass"
KEY_FILE="$CERT_DIR/lab-codesign.key"
CRT_FILE="$CERT_DIR/lab-codesign.crt"
PFX_FILE="$CERT_DIR/codesign.pfx"
CONFIG_FILE="$CERT_DIR/lab-codesign.openssl.cnf"

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

if [[ ! -s "$PASS_FILE" ]]; then
  openssl rand -base64 32 > "$PASS_FILE"
  chmod 600 "$PASS_FILE"
fi

cat > "$CONFIG_FILE" <<'OPENSSL_CONF'
[ req ]
default_bits       = 3072
distinguished_name = req_distinguished_name
x509_extensions    = v3_codesign
prompt             = no

[ req_distinguished_name ]
CN = Zenthralix Lab Code Signing
O  = zenthralix-lab
OU = NeoOptimize
C  = ID

[ v3_codesign ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
OPENSSL_CONF

openssl req -x509 -newkey rsa:3072 -sha256 -nodes \
  -days 825 \
  -keyout "$KEY_FILE" \
  -out "$CRT_FILE" \
  -config "$CONFIG_FILE" >/dev/null 2>&1

openssl pkcs12 -export \
  -inkey "$KEY_FILE" \
  -in "$CRT_FILE" \
  -name "Zenthralix Lab Code Signing" \
  -out "$PFX_FILE" \
  -passout "file:$PASS_FILE" >/dev/null 2>&1

chmod 600 "$KEY_FILE" "$CRT_FILE" "$PFX_FILE"

echo "Created lab code-signing certificate:"
echo "  PFX:  $PFX_FILE"
echo "  CRT:  $CRT_FILE"
echo "  PASS: $PASS_FILE"
echo ""
echo "Production SmartScreen note:"
echo "  Replace this lab certificate with a trusted OV/EV code-signing certificate."
