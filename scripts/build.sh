#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="$PWD/dist/Codex Quota.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist/AppIcon.iconset
cp .build/release/CodexQuota "$app/Contents/MacOS/CodexQuota"
cp Resources/Info.plist "$app/Contents/Info.plist"
xcrun swift scripts/make-icon.swift "$PWD/dist/AppIcon.iconset"
iconutil -c icns dist/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
printf '%s\n' "$app"
