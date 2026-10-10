#!/bin/zsh
# Build Turntable Mixer, check its signature, install it to ~/Applications.
# Fails on an ad hoc signature: macOS ties permissions to the signing team (spec D5).
set -euo pipefail
cd "${0:A:h}/.."
if [[ ! -f Local.xcconfig ]]; then
  print -u2 "FAIL: Local.xcconfig is missing. Create it with one line: DEVELOPMENT_TEAM = <your team ID>"
  exit 1
fi
xcodebuild -project TurntableMixer.xcodeproj -scheme TurntableMixer -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates -quiet build
app="build/Build/Products/Release/Turntable Mixer.app"
sig=$(codesign -dvv "$app" 2>&1)
if ! print -r -- "$sig" | grep -q '^Authority=Apple Development' || print -r -- "$sig" | grep -q '^TeamIdentifier=not set'; then
  print -u2 "FAIL: the app has no Apple Development signature with a team. Check Signing & Capabilities in Xcode."
  exit 1
fi
mkdir -p ~/Applications
rm -rf ~/Applications/"Turntable Mixer.app"
cp -R "$app" ~/Applications/
print "OK: installed ~/Applications/Turntable Mixer.app"
# Launch Services must know only the installed copy, or "Quit & Reopen" can launch a stale build.
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSR" -u "$PWD/$app" || true
"$LSR" -f ~/Applications/"Turntable Mixer.app"
"$LSR" -dump | grep -E '^path:.*Turntable Mixer\.app' | sed -E 's/^path: +//; s/ \(0x[0-9a-f]+\)$//' | sort -u | grep -vxF "$HOME/Applications/Turntable Mixer.app" | while read -r p; do
  print -u2 "WARNING: still registered with Launch Services: $p"
done || true
