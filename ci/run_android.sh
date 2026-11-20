#!/usr/bin/env bash
# Android (inside the emulator runner). Prints only PASS/FAIL lines; everything else goes to out/ (encrypted after).
#  android_install  the build installs
#  android_title    launched normally: screenshots every 4 s for ~1.5 min, one tap; pass = still running, no crash
#  android_blast    launched with Godot's command_line_params (a QA test): pass = its OK line in the log
set -u
T=${RUNNER_TEMP:?}
OUT=out
mkdir -p "$OUT/shots" "$OUT/logs"
APK=$(ls work/*.apk | head -1)
PKG=$(cat work/package.txt 2>/dev/null)
ACT="$PKG/com.godot.game.GodotAppLauncher"
shot() {   # the emulator's own screenshot from the host side (works when the guest's screencap is black), else screencap
  local f=$1
  adb emu screenrecord screenshot "$PWD/$f" >/dev/null 2>&1
  [ -s "$f" ] || adb exec-out screencap -p > "$f" 2>/dev/null
}
if ! adb install -r "$APK" >/dev/null 2>&1; then echo "FAIL android_install"; touch "$T/failed"; exit 0; fi
echo "PASS android_install"
# 1: the title
adb logcat -c >/dev/null 2>&1
adb shell am start -n "$ACT" >/dev/null 2>&1
for i in $(seq -w 1 24); do
  sleep 4
  shot "$OUT/shots/title_$i.png"
  [ "$i" = "14" ] && adb shell input tap 640 360 >/dev/null 2>&1
done
alive=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
adb logcat -d > "$OUT/logs/logcat_title.txt" 2>/dev/null
crash=$(grep -cE "FATAL EXCEPTION|SIGSEGV|SIGABRT|SCRIPT ERROR" "$OUT/logs/logcat_title.txt")
echo "# Android title: alive=${alive:-no} crash_lines=$crash" > "$OUT/summary.md"
if [ -n "$alive" ] && [ "$crash" = "0" ]; then echo "PASS android_title"; else echo "FAIL android_title"; touch "$T/failed"; fi
adb shell am force-stop "$PKG" >/dev/null 2>&1
sleep 2
# 2: a QA test on the phone build (the blast test: people, gore, fire)
adb logcat -c >/dev/null 2>&1
adb shell am start -n "$ACT" --esa command_line_params "--scene=world,--qa=blast_throw,--set=npc_density=0,--set=traffic=0" >/dev/null 2>&1
res=""
for i in $(seq -w 1 75); do
  sleep 4
  [ $((10#$i % 3)) = 0 ] && shot "$OUT/shots/blast_$i.png"
  res=$(adb logcat -d 2>/dev/null | grep -oE "BLAST (OK|FAIL).*" | tail -1)
  [ -n "$res" ] && break
done
adb logcat -d > "$OUT/logs/logcat_blast.txt" 2>/dev/null
echo "# Android blast: ${res:-no result}" >> "$OUT/summary.md"
grep -E "^\S+ \S+ +[0-9]+ +[0-9]+ I godot +:   (ok|FAIL) " "$OUT/logs/logcat_blast.txt" | sed 's/.*godot *: /    /' >> "$OUT/summary.md"
case "$res" in "BLAST OK"*) echo "PASS android_blast";; *) echo "FAIL android_blast"; touch "$T/failed";; esac
adb shell am force-stop "$PKG" >/dev/null 2>&1
python3 ci/sheets_android.py "$OUT" >/dev/null 2>&1 || true
exit 0
