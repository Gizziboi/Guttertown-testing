#!/usr/bin/env bash
# Decrypts plan.p7m into $RUNNER_TEMP (plan.json, coverage.json). The key exists only for this script.
set -eu
T=${RUNNER_TEMP:?}
umask 077
K="$T/.k.pem"
trap 'rm -f "${K:?}"' EXIT
bash ci/key.sh "$K"
OSSL=openssl; [ -x /usr/bin/openssl ] && [ "$(uname -s)" = Darwin ] && OSSL=/usr/bin/openssl
"$OSSL" smime -decrypt -binary -inform DER -inkey "$K" -in plan.p7m -out "$T/plan.tgz" >/dev/null 2>&1 \
  || openssl smime -decrypt -binary -inform DER -inkey "$K" -in plan.p7m -out "$T/plan.tgz" >/dev/null 2>&1
tar -xzf "$T/plan.tgz" -C "$T" >/dev/null 2>&1
rm -f "$T/plan.tgz" plan.p7m
echo "plan ready"
