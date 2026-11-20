#!/usr/bin/env bash
# Decrypt the build for this job (linux | mac | android). The key only exists in $RUNNER_TEMP for this script.
set -eu
TAG=${1:?}
T=${RUNNER_TEMP:?}
umask 077
K="$T/.k.pem"
trap 'rm -f "${K:?}"' EXIT
bash ci/key.sh "$K"
cat build/"$TAG".p7m.part-* > "$T/$TAG.p7m"
( cd build && shasum -a 256 -c "$TAG.sha256" >/dev/null 2>&1 ) || { echo "build parts corrupted"; exit 1; }
mkdir -p work
OSSL=openssl
[ "$TAG" = "mac" ] && OSSL=/usr/bin/openssl
"$OSSL" smime -decrypt -binary -inform DER -inkey "$K" -in "$T/$TAG.p7m" -out "$T/$TAG.tar" >/dev/null 2>&1 \
  || openssl smime -decrypt -binary -inform DER -inkey "$K" -in "$T/$TAG.p7m" -out "$T/$TAG.tar" >/dev/null 2>&1 \
  || { echo "decrypt failed"; exit 1; }
rm -f "${K:?}"
tar -xf "$T/$TAG.tar" -C work >/dev/null 2>&1
rm -f "${T:?}/${TAG:?}.p7m" "${T:?}/${TAG:?}.tar"
if [ "$TAG" = "mac" ]; then ( cd work && unzip -q game.zip >/dev/null 2>&1 && rm -f game.zip ); fi
echo "build ready"
