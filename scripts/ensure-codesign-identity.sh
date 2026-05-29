#!/usr/bin/env zsh
set -euo pipefail

IDENTITY_NAME="${FLOWY_CODESIGN_IDENTITY:-Flowy Local Development}"
REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
CERT_DIR="$REPO_ROOT/.build/codesign"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

MATCH_COUNT="$(
  security find-certificate -a -c "$IDENTITY_NAME" "$KEYCHAIN" 2>/dev/null \
    | grep -c 'alis' || true
)"

if [[ "$MATCH_COUNT" == "1" ]] \
  && security find-identity -v -p codesigning "$KEYCHAIN" | grep -F "$IDENTITY_NAME" >/dev/null; then
  echo "$IDENTITY_NAME"
  exit 0
fi

mkdir -p "$CERT_DIR"
while security delete-identity -t -c "$IDENTITY_NAME" "$KEYCHAIN" >/dev/null 2>&1; do
  :
done
while security delete-certificate -t -c "$IDENTITY_NAME" "$KEYCHAIN" >/dev/null 2>&1; do
  :
done
rm -f \
  "$CERT_DIR/flowey-codesign.key" \
  "$CERT_DIR/flowey-codesign.crt" \
  "$CERT_DIR/flowey-codesign.p12"

cat > "$CERT_DIR/codesign.cnf" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = ext

[ dn ]
CN = $IDENTITY_NAME

[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -nodes \
  -days 3650 \
  -config "$CERT_DIR/codesign.cnf" \
  -keyout "$CERT_DIR/flowey-codesign.key" \
  -out "$CERT_DIR/flowey-codesign.crt" >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$CERT_DIR/flowey-codesign.key" \
  -in "$CERT_DIR/flowey-codesign.crt" \
  -name "$IDENTITY_NAME" \
  -out "$CERT_DIR/flowey-codesign.p12" \
  -passout pass:flowey-local-dev >/dev/null 2>&1

security import "$CERT_DIR/flowey-codesign.p12" \
  -k "$KEYCHAIN" \
  -P "flowey-local-dev" \
  -T /usr/bin/codesign >/dev/null

security add-trusted-cert \
  -d \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERT_DIR/flowey-codesign.crt" >/dev/null 2>&1 || true

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "" \
  "$KEYCHAIN" >/dev/null 2>&1 || true

echo "$IDENTITY_NAME"
