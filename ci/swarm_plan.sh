#!/usr/bin/env bash
# Plan job: the game writes its coverage map (tests/bots/coverage.gd), the planner deals it out to 115 bots,
# and plan + coverage go out encrypted (plan.p7m). Prints only PASS/FAIL coverage.
set -u
RUN=${1:?}
T=${RUNNER_TEMP:?}
mkdir -p "$T/cov"
BIN="$PWD/work/guttertown.x86_64"; chmod +x "$BIN"
Xvfb :99 -screen 0 1280x720x24 >/dev/null 2>&1 &
export DISPLAY=:99 VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
sleep 2
timeout 600 "$BIN" --rendering-method mobile --rendering-driver vulkan --audio-driver Dummy --resolution 1280x720 -- \
  --scene=world --world-seed=42 --set=show_guide=false --qa=bots/coverage --out="$T/cov" > "$T/cov/coverage.log" 2>&1 < /dev/null
if [ -s "$T/cov/coverage.json" ]; then echo "PASS coverage"; else echo "FAIL coverage"; exit 1; fi
python3 ci/swarm_plan.py "$T/cov/coverage.json" "$RUN" "$T/cov/plan.json" > "$T/cov/plan.txt"
if [ -n "${SECS:-}" ]; then
  python3 - "$T/cov/plan.json" "$SECS" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); s = int(sys.argv[2])
for b in p["bots"]: b["secs"] = min(s, 1500)
json.dump(p, open(sys.argv[1], "w"), indent=1)
PY
fi
tar -czf "$T/plan.tgz" -C "$T/cov" . >/dev/null 2>&1
openssl smime -encrypt -binary -aes256 -outform DER -in "$T/plan.tgz" -out plan.p7m ci/public_key.pem >/dev/null 2>&1
rm -rf "$T/plan.tgz" "$T/cov"
echo "plan encrypted"
