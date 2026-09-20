#!/usr/bin/env bash
# Launches the built app in the iOS Simulator with demo data and saves one screenshot per screen.
# Expects the app to be built with -derivedDataPath build. Run from the repo root.
set -euo pipefail

mkdir -p screenshots
BUNDLE=com.terminalasset.app

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

# shot <name> <appearance> [launch arguments...]
shot() {
  local name="$1" mode="$2"
  shift 2
  xcrun simctl ui "$UDID" appearance "$mode"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" -sampleData "$@" >/dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot "screenshots/$name.png"
}

shot today-light light
shot today-dark dark
shot weather-clear light -weather clear
shot today-hourly light -weather rain -todaySection hourly
shot today-loose-ends light -todaySection looseEnds
shot today-daily light -weather partlyCloudy -todaySection daily
shot today-details dark -weather clear -night -todaySection details
shot weather-rain light -weather rain
shot weather-night dark -weather clear -night
shot weather-storm dark -weather thunderstorm
shot weather-permission light -weatherPermission
shot calendar-month light -calendar month
shot calendar-day light -calendar day
shot event-detail light -detail
shot add-task light -detail -addSheet task
shot search light -tab search
shot search-results light -tab search -query audit
shot inbox light -tab inbox
shot calendar-tab light -tab calendar
shot settings light -tab settings
shot cloud-privacy light -tab settings -privacy
shot paywall light -tab settings -paywall
shot onboarding light -onboarding

# Real location + real Open-Meteo request (needs network). The simulator is placed in Bangkok and location
# permission is pre-granted, so this exercises CoreLocation, geocoding and the HTTP call end to end.
xcrun simctl privacy "$UDID" grant location "$BUNDLE" || true
xcrun simctl location "$UDID" set 13.7563,100.5018 || true
xcrun simctl ui "$UDID" appearance light
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE" -sampleData -liveWeather >/dev/null
sleep 16
xcrun simctl io "$UDID" screenshot "screenshots/weather-live.png"

# Same real request, scrolled to the 7-day forecast and detail tiles.
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE" -sampleData -liveWeather -todaySection daily >/dev/null
sleep 16
xcrun simctl io "$UDID" screenshot "screenshots/weather-live-forecast.png"

ls -la screenshots
