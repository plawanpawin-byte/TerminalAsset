#!/usr/bin/env bash
# Builds and tests the package on macOS (e.g. a MacinCloud machine). Run from the repo root.
set -euo pipefail

echo "== Toolchain =="
xcodebuild -version
swift --version

echo "== swift build (macOS) =="
swift build

echo "== swift test (Domain + Core, macOS) =="
swift test

echo "== xcodebuild (iOS Simulator, Core library) =="
xcodebuild build \
  -scheme TerminalAssetCore \
  -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation

echo "All checks passed."
