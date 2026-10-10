#!/bin/zsh
# Render the UI offscreen to PNG (light and dark) with fixture data. No audio, no Screen Recording permission.
# Usage: scripts/snapshot.sh [output-dir]   (default build/snapshots)
set -euo pipefail
cd "${0:A:h}/.."
out="${1:-build/snapshots}"
mkdir -p "$out" build
files=(TurntableMixer/*.swift)
files=("${(@)files:#TurntableMixer/TurntableMixerApp.swift}")
swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  -framework SwiftUI -framework AppKit -framework AVFoundation -framework CoreAudio \
  "${files[@]}" scripts/snapshot.swift -o build/snapshot
build/snapshot "$out"
