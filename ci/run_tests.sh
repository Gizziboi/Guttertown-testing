#!/usr/bin/env bash
# Linux / Mac: run each QA test from the exported build in a real window, with a whole-screen screenshot loop and
# (Linux) a screen recording per test. Prints ONLY "PASS <test>" / "FAIL <test>"; everything else goes to out/
# (encrypted before anything is uploaded).
set -u
TAG=${1:?}
T=${RUNNER_TEMP:?}
OUT=out
mkdir -p "$OUT/loop" "$OUT/logs" "$OUT/video"
OS=$(uname -s)
if [ "$TAG" = "linux" ]; then
  BIN="$PWD/work/guttertown.x86_64"; chmod +x "$BIN"
  Xvfb :99 -screen 0 1280x720x24 >/dev/null 2>&1 &
  export DISPLAY=:99; sleep 2
  export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
  ARGS=(--rendering-method mobile --rendering-driver vulkan --audio-driver Dummy --resolution 1280x720 --position 0,0)
else
  APP=$(ls -d "$PWD"/work/*.app | head -1)
  BIN="$APP/Contents/MacOS/$(ls "$APP/Contents/MacOS" | head -1)"
  xattr -cr "$APP" >/dev/null 2>&1 || true
  ARGS=(--rendering-method mobile --audio-driver Dummy --resolution 1280x720 --position 0,0)
fi
if command -v timeout >/dev/null; then TO=timeout; elif command -v gtimeout >/dev/null; then TO=gtimeout; else TO=""; fi
cp work/build_info.txt "$OUT/" 2>/dev/null || true
echo "# GUTTERTOWN cloud QA - $(head -1 work/build_info.txt 2>/dev/null) - $OS - $(date -u +%FT%TZ)" > "$OUT/summary.md"
echo "" >> "$OUT/summary.md"
(
  i=0
  while [ ! -f "$OUT/.stop" ]; do
    f=$(printf "%s/loop/f%05d.png" "$OUT" $i)
    if [ "$OS" = "Darwin" ]; then screencapture -x -t png "$f" >/dev/null 2>&1; else import -display "$DISPLAY" -window root "$f" >/dev/null 2>&1; fi
    [ -f "$f" ] && echo "$(date +%s) $(cat "$OUT/.cur" 2>/dev/null)" > "${f%.png}.txt"
    i=$((i + 1)); sleep 2
  done
) >/dev/null 2>&1 &
LOOP=$!
while IFS='|' read -r name tmo args; do
  [ -z "$name" ] && continue
  case "$name" in \#*) continue;; esac
  echo "$name" > "$OUT/.cur"
  log="$OUT/logs/$name.log"
  REC=""
  if [ "$TAG" = "linux" ]; then
    ffmpeg -v quiet -y -f x11grab -framerate 8 -video_size 1280x720 -i "$DISPLAY" -c:v libx264 -preset veryfast -crf 32 -pix_fmt yuv420p "$OUT/video/$name.mp4" >/dev/null 2>&1 &
    REC=$!
  fi
  t0=$(date +%s)
  # shellcheck disable=SC2086
  $TO "$tmo" "$BIN" "${ARGS[@]}" -- $args > "$log" 2>&1 < /dev/null
  rc=$?
  [ -n "$REC" ] && { kill -INT "$REC" >/dev/null 2>&1; wait "$REC" >/dev/null 2>&1; }
  dur=$(( $(date +%s) - t0 ))
  errs=$(grep -c "SCRIPT ERROR" "$log")
  res=$(grep -E "RESULT|TEST (OK|FAIL)|^[A-Z_]+ (OK|FAIL|PASS|CLEAN|CHECK)" "$log" | tail -1 | cut -c1-200)
  v=PASS
  { [ $rc -ne 0 ] || [ "$errs" -gt 0 ] || [[ "$res" == *FAIL* ]] || [[ "$res" == *"RESULT CHECK"* ]] || [ -z "$res" ]; } && v=FAIL
  [ $rc -eq 124 ] && res="TIMEOUT after ${tmo}s; $res"
  echo "- **$name** $v (${dur}s, rc=$rc, script errors=$errs): $res" >> "$OUT/summary.md"
  grep -E "^  (ok|FAIL) |^    " "$log" | head -60 | sed 's/^/    /' >> "$OUT/summary.md"
  echo "$v $name"
  [ "$v" = FAIL ] && touch "$T/failed"
done < "ci/tests_$TAG.txt"
touch "$OUT/.stop"; wait $LOOP 2>/dev/null
rm -f "$OUT/.stop" "$OUT/.cur"
# the pictures the tests take themselves
mkdir -p "$OUT/test_shots"
for d in blast wire_car car_menu dash exec walls; do [ -d "/tmp/$d" ] && cp -R "/tmp/$d" "$OUT/test_shots/" >/dev/null 2>&1; done
python3 ci/sheets.py "$OUT" >/dev/null 2>&1 || true
exit 0
