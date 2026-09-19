#!/usr/bin/env bash
# Generates TerminalAsset.xcodeproj from project.yml and opens it in Xcode. Run from the repo root on a Mac.
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing XcodeGen with Homebrew…"
    brew install xcodegen
  else
    echo "XcodeGen is required. Install Homebrew (https://brew.sh) and run: brew install xcodegen" >&2
    exit 1
  fi
fi

xcodegen generate
open TerminalAsset.xcodeproj
echo "Opened TerminalAsset.xcodeproj. Choose the TerminalAsset scheme and an iPhone Simulator, then press Run."
