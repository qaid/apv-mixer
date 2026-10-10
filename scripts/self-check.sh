#!/bin/zsh
# Audio self-check: confirms an app strip appears, its needle moves and its tap delivers audio, by reading the app's log.
# Run after scripts/build.sh. Needs no audio hardware knowledge, but:
#  - It plays a quiet 440 Hz tone (-20 dBFS, 10 s) through the speakers. Do not run it while listening to something.
#  - Playback uses QuickTime Player (a process with a bundle ID, so it gets a strip) driven by osascript.
#    The first run shows a one-time macOS Automation prompt: allow your terminal to control QuickTime Player.
#  - It quits and relaunches Turntable Mixer, and sets then deletes the "selfCheckLog" default.
set -uo pipefail
bid=io.github.qaid.turntablemixer
app=~/Applications/"Turntable Mixer.app"
tmp=$(mktemp -d)
tone="$tmp/tone.wav"
logf="$tmp/selfcheck.log"

relaunch() { osascript -e 'quit app "Turntable Mixer"' >/dev/null 2>&1; sleep 2; open "$app"; }
cleanup() {
  osascript -e 'tell application "QuickTime Player" to quit' >/dev/null 2>&1
  [[ -n "${lpid:-}" ]] && kill "$lpid" 2>/dev/null
  defaults delete $bid selfCheckLog 2>/dev/null
  relaunch
  rm -rf "$tmp"
}
trap cleanup EXIT

python3 -I - "$tone" <<'PY'
import math, struct, sys, wave
w = wave.open(sys.argv[1], "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
w.writeframes(b"".join(struct.pack("<h", int(32767 * 0.1 * math.sin(2 * math.pi * 440 * i / 44100))) for i in range(441000)))
w.close()
PY

defaults write $bid selfCheckLog -bool YES
relaunch
sleep 3

/usr/bin/log stream --style compact --predicate "subsystem == \"$bid\" AND category == \"selfcheck\"" > "$logf" 2>&1 &
lpid=$!
sleep 1
open -a "QuickTime Player" "$tone"
sleep 2
osascript -e 'tell application "QuickTime Player" to play document 1' || print -u2 "WARNING: could not start playback (Automation permission?)"
sleep 8
osascript -e 'tell application "QuickTime Player" to stop document 1' >/dev/null 2>&1
kill "$lpid" 2>/dev/null; lpid=

best=$(awk '/ app name=QuickTime/ { for (i=1;i<=NF;i++) if ($i ~ /^needleDB=/) { v=substr($i,10)+0; if (!n || v>m) { m=v; n=1 } } } END { if (n) print m }' "$logf")
off=$(grep -c 'captureMaybeOff=true' "$logf")
print "captureMaybeOff went true: $([[ $off -gt 0 ]] && print yes || print no)"
if [[ -n "$best" ]] && (( best > -50 )); then
  print "PASS: QuickTime Player strip appeared, peak needle $best dB (floor -60)"
else
  print "FAIL: no QuickTime Player strip with needle above -50 dB (best: ${best:-none}). Last log lines:"
  tail -n 12 "$logf"
  exit 1
fi
