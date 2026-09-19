#!/usr/bin/env bash
# Launches the built app in the iOS Simulator with demo data and saves light/dark screenshots.
# Expects the app to be built with -derivedDataPath build. Run from the repo root.
set -euo pipefail

mkdir -p screenshots

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
phones = [d for runtime, ds in devices.items() if "iOS" in runtime for d in ds if "iPhone" in d["name"]]
phones.sort(key=lambda d: ("Pro" not in d["name"], "Max" in d["name"], d["name"]))
print(phones[0]["udid"])
')
echo "Using simulator $UDID"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

APP=$(find build/Build/Products -maxdepth 3 -name 'TerminalAsset.app' | head -1)
xcrun simctl install "$UDID" "$APP"

for mode in light dark; do
  xcrun simctl ui "$UDID" appearance "$mode"
  xcrun simctl terminate "$UDID" com.terminalasset.app || true
  xcrun simctl launch "$UDID" com.terminalasset.app -sampleData
  sleep 8
  xcrun simctl io "$UDID" screenshot "screenshots/today-$mode.png"
done
ls -la screenshots
