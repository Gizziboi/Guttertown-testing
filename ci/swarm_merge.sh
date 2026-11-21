#!/usr/bin/env bash
# Summary job: decrypt every job's results, merge them into one report (ci/swarm_summary.py) and copy it,
# unencrypted, to the private repo's test-results branch: swarm/runs/<run>/ (REPORT.md, bugs/, COVERAGE.md),
# swarm/latest.json and swarm/baseline/ (the known-good pictures). Prints only PASS/FAIL swarm.
set -u
RUN=${1:?}
T=${RUNNER_TEMP:?}
umask 077
K="$T/.k.pem"
trap 'rm -f "${K:?}"' EXIT
bash ci/key.sh "$K"
mkdir -p res rep
dec() { openssl smime -decrypt -binary -inform DER -inkey "$K" -in "$1" -out "$2" >/dev/null 2>&1; }
dec arts/swarm-plan/plan.p7m "$T/plan.tgz" && tar -xzf "$T/plan.tgz" -C "$T" >/dev/null 2>&1
for f in arts/swarm-res-*/*.p7m; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .p7m); mkdir -p "res/$n"
  dec "$f" "$T/r.tgz" && tar -xzf "$T/r.tgz" -C "res/$n" >/dev/null 2>&1
  rm -f "$T/r.tgz"
done
rm -f "$K"
H=""
PRIV="$T/priv"
if [ -n "${GUTTERTOWN_PRIVATE_TOKEN:-}" ]; then
  H="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GUTTERTOWN_PRIVATE_TOKEN" | base64 | tr -d '\n')"
  git -c http.extraheader="$H" clone -q --depth 1 --branch test-results https://github.com/Gizziboi/guttertown "$PRIV" >/dev/null 2>&1 || mkdir -p "$PRIV"
fi
mkdir -p "$PRIV/swarm"
python3 ci/swarm_summary.py res "$T/coverage.json" "$T/plan.json" "$PRIV/swarm" rep 2> "$T/summary_err.txt" | grep -E "^(PASS|FAIL) swarm" || echo "FAIL swarm"
cp "$T/COVERAGE.md" rep/ 2>/dev/null || true
cp "$T/summary_err.txt" rep/ 2>/dev/null || true
[ -z "$H" ] && { echo "no private token: report not copied"; exit 0; }
for i in 1 2 3 4 5; do
  (
    cd "$PRIV" || exit 1
    git rev-parse --git-dir >/dev/null 2>&1 || { git init -q && git checkout -q -b test-results && git remote add origin https://github.com/Gizziboi/guttertown; }
    git config user.name "guttertown-qa"; git config user.email "qa@users.noreply.github.com"
    D="swarm/runs/$(printf '%05d' "$RUN")"
    mkdir -p "$D" swarm/baseline
    cp -R "$GITHUB_WORKSPACE/rep/." "$D/"
    [ -d "$D/baseline" ] && { cp -R "$D/baseline/." swarm/baseline/; rm -rf "$D/baseline"; }
    cp "$D/latest.json" swarm/latest.json
    cp "$D/COVERAGE.md" swarm/COVERAGE.md 2>/dev/null || true
    ls -d swarm/runs/* | sort | head -n -10 | while read -r o; do git rm -rq "$o" >/dev/null 2>&1; done
    git add -A >/dev/null 2>&1 && git commit -qm "swarm run $RUN" >/dev/null 2>&1
    git -c http.extraheader="$H" push -q origin test-results >/dev/null 2>&1
  ) && { echo "report copied to the private repo"; exit 0; }
  sleep $((i * 6))
  ( cd "$PRIV" && git -c http.extraheader="$H" pull -q --rebase origin test-results >/dev/null 2>&1 ) || true
done
echo "copy to the private repo failed"
