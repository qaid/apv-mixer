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
