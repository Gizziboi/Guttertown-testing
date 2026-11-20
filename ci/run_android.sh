#!/usr/bin/env bash
# Android (inside the emulator runner). Prints only PASS/FAIL lines; everything else goes to out/ (encrypted after).
# The QA phone build starts in OpenGL (the emulator's Vulkan can't present) and runs a QA test by itself (the blast:
# the city, people, fire, gore), baked into the build.
#  android_install  the build installs
#  android_test     its result line in the log is OK (no crash, no script error); a screenshot every 4 s meanwhile
set -u
T=${RUNNER_TEMP:?}
OUT=out
mkdir -p "$OUT/shots" "$OUT/logs"
APK=$(ls work/*.apk | head -1)
PKG=$(cat work/package.txt 2>/dev/null)
shot() {   # the guest's screencap, else the emulator's own screenshot from the host side
  local f=$1
  adb exec-out screencap -p > "$f" 2>/dev/null
  [ -s "$f" ] || adb emu screenrecord screenshot "$PWD/$f" >/dev/null 2>&1
}
if ! adb install -r "$APK" >/dev/null 2>&1; then echo "FAIL android_install"; touch "$T/failed"; exit 0; fi
echo "PASS android_install"
adb logcat -c >/dev/null 2>&1
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
res=""
for i in $(seq -w 1 90); do
  sleep 4
  shot "$OUT/shots/a$i.png"
  res=$(adb logcat -d 2>/dev/null | grep -oE "BLAST (OK|FAIL).*" | tail -1)
  [ -n "$res" ] && break
done
sleep 2
adb logcat -d > "$OUT/logs/logcat.txt" 2>/dev/null
crash=$(grep -cE "FATAL EXCEPTION|SIGSEGV|SIGABRT|SCRIPT ERROR" "$OUT/logs/logcat.txt")
{
  echo "# Android: ${res:-no result} (crash / script error lines: $crash)"
  grep -E " I godot +:   (ok|FAIL) | I godot +:     " "$OUT/logs/logcat.txt" | sed 's/.*godot *: /    /'
} > "$OUT/summary.md"
python3 ci/sheets_android.py "$OUT" >/dev/null 2>&1 || true
case "$res" in "BLAST OK"*) [ "$crash" = "0" ] && { echo "PASS android_test"; exit 0; };; esac
echo "FAIL android_test"; touch "$T/failed"
exit 0
