#!/usr/bin/env bash
# Pack everything the run produced and encrypt it to the public certificate (AES-256). Only the .p7m is uploaded.
TAG=${1:?}
[ -d out ] || mkdir -p out
tar -czf "results-$TAG.tgz" -C out . >/dev/null 2>&1
openssl smime -encrypt -binary -aes256 -outform DER -in "results-$TAG.tgz" -out "results-$TAG.p7m" ci/public_key.pem >/dev/null 2>&1 \
  && echo "results encrypted" || echo "encrypt failed"
rm -f "results-${TAG:?}.tgz"
