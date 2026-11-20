#!/usr/bin/env bash
# Android (inside the emulator runner): install the build, start it, a screenshot every 4 s for ~2.5 min, logcat.
# Pass = it's still running at the end with no crash / script error in its log. Prints only PASS/FAIL lines.
set -u
T=${RUNNER_TEMP:?}
OUT=out
mkdir -p "$OUT/shots" "$OUT/logs"
APK=$(ls work/*.apk | head -1)
PKG=$(cat work/package.txt 2>/dev/null)
if ! adb install -r "$APK" >/dev/null 2>&1; then echo "FAIL android_install"; touch "$T/failed"; exit 0; fi
echo "PASS android_install"
adb logcat -c >/dev/null 2>&1
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
for i in $(seq -w 1 38); do
  sleep 4
  adb exec-out screencap -p > "$OUT/shots/a$i.png" 2>/dev/null
  # one tap in the middle once the title is up
  [ "$i" = "12" ] && adb shell input tap 640 360 >/dev/null 2>&1
done
alive=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
adb logcat -d > "$OUT/logs/logcat.txt" 2>/dev/null
crash=$(grep -cE "FATAL EXCEPTION|SIGSEGV|SIGABRT|SCRIPT ERROR" "$OUT/logs/logcat.txt")
echo "# Android: alive=${alive:-no} crash_lines=$crash" > "$OUT/summary.md"
python3 ci/sheets_android.py "$OUT" >/dev/null 2>&1 || true
if [ -n "$alive" ] && [ "$crash" = "0" ]; then echo "PASS android_run"; else echo "FAIL android_run"; touch "$T/failed"; fi
exit 0
