#!/usr/bin/env bash
# One swarm job: runs this job's bots (3 on Linux, 2 on Mac) at the same time, each its own game instance with
# its own display (Linux: Xvfb :99+), its own user data folder and its own output folder. Prints ONLY
# "PASS bot-<id>" / "FAIL bot-<id>"; everything else goes to out/ (encrypted before upload).
#   swarm_run.sh linux|mac JOB_INDEX
set -u
TAG=${1:?}; JOB=${2:?}
T=${RUNNER_TEMP:?}
OUT="$PWD/out"
mkdir -p "$OUT"
if [ "$TAG" = "linux" ]; then
  BIN="$PWD/work/guttertown.x86_64"; chmod +x "$BIN"
  export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
  ARGS=(--rendering-method mobile --rendering-driver vulkan --audio-driver Dummy --resolution 1280x720 --position 0,0)
else
  APP=$(ls -d "$PWD"/work/*.app | head -1)
  BIN="$APP/Contents/MacOS/$(ls "$APP/Contents/MacOS" | head -1)"
  xattr -cr "$APP" >/dev/null 2>&1 || true
  ARGS=(--rendering-method mobile --audio-driver Dummy --resolution 1280x720)
fi
if command -v timeout >/dev/null; then TO=timeout; elif command -v gtimeout >/dev/null; then TO=gtimeout; else TO=""; fi
python3 - "$T/plan.json" "$TAG" "$JOB" "$OUT" > "$T/mybots.txt" <<'PY'
import json, sys, os
plan = json.load(open(sys.argv[1])); tag, job, out = sys.argv[2], int(sys.argv[3]), sys.argv[4]
for b in plan["bots"]:
    if b["os"] == tag and b["job"] == job:
        d = os.path.join(out, "bots", b["bot"]); os.makedirs(d, exist_ok=True)
        json.dump(b["assign"], open(os.path.join(d, "assign.json"), "w"))
        json.dump(b, open(os.path.join(d, "plan.json"), "w"))
        print("|".join(str(x) for x in [b["bot"], b["slot"], b["role"], b["seed"], b["world_seed"], b["secs"], " ".join(b.get("extra", []))]))
PY
pids=()
names=()
while IFS='|' read -r bot slot role seed wseed secs pextra; do
  [ -z "$bot" ] && continue
  d="$OUT/bots/$bot"
  u="$T/user_$bot"; mkdir -p "$u"
  extra=()
  [ "$role" = "visual" ] && extra=(--set=weather=clear --set=npc_density=0 --set=traffic=0)
  # shellcheck disable=SC2206
  [ -n "$pextra" ] && extra=($pextra)
  (
    if [ "$TAG" = "linux" ]; then
      disp=$((99 + slot))
      Xvfb ":$disp" -screen 0 1280x720x24 >/dev/null 2>&1 &
      XV=$!
      sleep 2
      export DISPLAY=":$disp" XDG_DATA_HOME="$u" XDG_CONFIG_HOME="$u/cfg"
    else
      export HOME="$u"
    fi
    t0=$(date +%s)
    # shellcheck disable=SC2086
    $TO $((secs + 240)) "$BIN" "${ARGS[@]}" -- --scene=world --world-seed="$wseed" --set=show_guide=false ${extra[@]+"${extra[@]}"} \
      --qa=bots/bot --role="$role" --bot="$bot" --bot-seed="$seed" --assign="$d/assign.json" --secs="$secs" --out="$d" \
      > "$d/game.log" 2>&1 < /dev/null
    echo "$? $(( $(date +%s) - t0 ))" > "$d/exit.txt"
    [ "$TAG" = "linux" ] && kill "$XV" >/dev/null 2>&1
    # the game's own logs for this instance (the reports folder is under the instance's home on the Mac)
    cp -R "$u"/godot/app_userdata/GUTTERTOWN/logs "$d/userlogs" >/dev/null 2>&1 || true
    cp -R "$u"/Library/Application\ Support/Godot/app_userdata/GUTTERTOWN/logs "$d/userlogs" >/dev/null 2>&1 || true
  ) &
  pids+=($!); names+=("$bot")
  sleep 3
done < "$T/mybots.txt"
for i in "${!pids[@]}"; do
  wait "${pids[$i]}"
  bot=${names[$i]}; d="$OUT/bots/$bot"
  rc=$(cut -d' ' -f1 "$d/exit.txt" 2>/dev/null || echo 99)
  last=$(grep -E "^BOT $bot (OK|FAIL)" "$d/game.log" | tail -1)
  if [ "$rc" = "0" ] && [[ "$last" == *" OK "* ]]; then echo "PASS bot-$bot"; else echo "FAIL bot-$bot"; touch "$T/failed"; fi
done
# short clips round each failure from its frames
for f in "$OUT"/bots/*/fail_*; do
  [ -d "$f" ] || continue
  ls "$f"/before_*.jpg "$f"/after_*.jpg 2>/dev/null | sort -t_ -k1,1r > "$f/frames.txt"
  i=0; mkdir -p "$f/seq"
  for j in $(ls "$f"/before_*.jpg 2>/dev/null | sort) $(ls "$f"/after_*.jpg 2>/dev/null | sort); do cp "$j" "$f/seq/$(printf %03d $i).jpg"; i=$((i+1)); done
  [ $i -gt 1 ] && ffmpeg -nostdin -v quiet -y -framerate 2 -i "$f/seq/%03d.jpg" -c:v libx264 -pix_fmt yuv420p -vf "scale=480:-2" "$f/clip.mp4" >/dev/null 2>&1
  rm -rf "$f/seq" "$f/frames.txt"
done
exit 0
