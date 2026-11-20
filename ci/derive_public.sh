#!/usr/bin/env bash
# Works out what GUTTERTOWN_KEY is and writes only its public half (never the key):
#   an RSA/EC private key (PEM, or PEM in base64)  -> ci/public_key.pem (a self-signed certificate: openssl smime, AES-256)
#   an age secret key (AGE-SECRET-KEY-1...)         -> ci/public_key.age (its recipient)
#   anything else (a passphrase)                    -> ci/public_key.type = "passphrase" (no public half exists)
set -u
umask 077
[ -n "${GUTTERTOWN_KEY:-}" ] || { echo "GUTTERTOWN_KEY secret is missing"; exit 1; }
K="$RUNNER_TEMP/.k"
trap 'rm -f "$K" "$K.pem"' EXIT
printf '%s' "$GUTTERTOWN_KEY" > "$K"
if grep -q "AGE-SECRET-KEY-1" "$K"; then
  sudo apt-get install -y -qq age >/dev/null 2>&1
  age-keygen -y "$K" > ci/public_key.age 2>/dev/null && echo age > ci/public_key.type && echo "type: age" && exit 0
fi
if grep -q "PRIVATE KEY" "$K"; then cp "$K" "$K.pem"; else base64 --decode "$K" > "$K.pem" 2>/dev/null || true; fi
if grep -q "PRIVATE KEY" "$K.pem" 2>/dev/null && openssl pkey -in "$K.pem" -noout >/dev/null 2>&1; then
  openssl req -new -x509 -key "$K.pem" -subj "/CN=guttertown-qa" -days 3650 -out ci/public_key.pem >/dev/null 2>&1 \
    && echo pem > ci/public_key.type && echo "type: private key (certificate written)" && exit 0
fi
echo passphrase > ci/public_key.type
echo "type: passphrase (no public half: see the README of the private repo)"
exit 0
