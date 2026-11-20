#!/usr/bin/env bash
# Copy the (unencrypted) results to the private repo, branch test-results, folder runs/<run>-<job>/ (newest 30 kept).
# The token is only ever passed in a git header; nothing it touches is echoed.
TAG=${1:?}; RUN=${2:?}
T=${RUNNER_TEMP:?}
[ -n "${GUTTERTOWN_PRIVATE_TOKEN:-}" ] || { echo "no private token: skipped"; exit 0; }
[ -d out ] || { echo "no results"; exit 0; }
H="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GUTTERTOWN_PRIVATE_TOKEN" | base64 | tr -d '\n')"
URL=https://github.com/Gizziboi/guttertown
D="runs/$(printf '%05d' "$RUN")-$TAG"
R="$T/res"
for i in 1 2 3 4 5; do
  rm -rf "${R:?}"
  if ! git -c http.extraheader="$H" clone -q --depth 1 --branch test-results "$URL" "$R" >/dev/null 2>&1; then
    mkdir -p "$R" && ( cd "$R" && git init -q && git checkout -q -b test-results && git remote add origin "$URL" )
  fi
  (
    cd "$R" || exit 1
    git config user.name "guttertown-qa"; git config user.email "qa@users.noreply.github.com"
    N=$(ls -d runs/* 2>/dev/null | wc -l)
    ls -d runs/* 2>/dev/null | sort | awk -v n="$N" 'NR <= n - 29' | while read -r o; do git rm -rq "$o" >/dev/null 2>&1; done
    mkdir -p "$D" && cp -R "$GITHUB_WORKSPACE/out/." "$D/"
    ls -d runs/* | sort -r > INDEX.txt
    git add -A >/dev/null 2>&1 && git commit -qm "results $D" >/dev/null 2>&1
    git -c http.extraheader="$H" push -q origin test-results >/dev/null 2>&1
  ) && { echo "copied to the private repo"; exit 0; }
  sleep $((i * 6))
done
echo "copy to the private repo failed"
