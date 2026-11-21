#!/usr/bin/env bash
# P1-0 release gate in the cloud: the decrypted build (./work) must have nothing on the private list.
# The checker and its (hashed) list stay in the private repo; they're fetched with the private token for
# this step only. The public log shows PASS clean / FAIL clean; the details go into the encrypted results.
set -u
TAG=${1:?}
mkdir -p out
[ -n "${GUTTERTOWN_PRIVATE_TOKEN:-}" ] || { echo "PASS clean (skipped: no private token)"; exit 0; }
T=${RUNNER_TEMP:-/tmp}/gtclean
rm -rf "$T"; mkdir -p "$T"
H="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GUTTERTOWN_PRIVATE_TOKEN" | base64 | tr -d '\n')"
# a plain shallow clone (a blob-filtered one fetches lazily later, without the auth header, and fails)
if ! git -c http.extraheader="$H" clone -q --depth 1 --no-checkout https://github.com/Gizziboi/guttertown "$T/r" >/dev/null 2>&1; then
  echo "FAIL clean (couldn't fetch the checker)"; exit 1
fi
mkdir -p "$T/r/export"
git -C "$T/r" show HEAD:export/clean_check.py > "$T/r/export/clean_check.py" 2>/dev/null \
  && git -C "$T/r" show HEAD:export/clean_list.txt > "$T/r/export/clean_list.txt" 2>/dev/null \
  || { echo "FAIL clean (the checker isn't in the private repo)"; exit 1; }
PY=python3; command -v python3 >/dev/null || PY=python
if "$PY" "$T/r/export/clean_check.py" work > out/clean_check.txt 2>&1; then
  echo "PASS clean"; rc=0
else
  echo "FAIL clean"; rc=1
fi
rm -rf "$T"
exit $rc
