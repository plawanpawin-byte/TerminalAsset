#!/usr/bin/env bash
# Generates TerminalAsset.xcodeproj from project.yml and opens it in Xcode. Run from the repo root on a Mac.
#
# XcodeGen is downloaded into .tools/ inside this folder when it is not already installed, so neither Homebrew
# nor administrator rights are needed (shared and rented Macs often have a read-only Homebrew).
set -euo pipefail

XCODEGEN_VERSION="2.46.0"
TOOLS_DIR=".tools"
LOCAL_BIN="$TOOLS_DIR/xcodegen/bin/xcodegen"

if command -v xcodegen >/dev/null 2>&1; then
  XCODEGEN="xcodegen"
elif [ -x "$LOCAL_BIN" ]; then
  XCODEGEN="$LOCAL_BIN"
else
  echo "Downloading XcodeGen $XCODEGEN_VERSION into $TOOLS_DIR/ …"
  mkdir -p "$TOOLS_DIR"
  curl -fL --retry 3 \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip" \
    -o "$TOOLS_DIR/xcodegen.zip"
  unzip -q -o "$TOOLS_DIR/xcodegen.zip" -d "$TOOLS_DIR"
  rm -f "$TOOLS_DIR/xcodegen.zip"
  chmod +x "$LOCAL_BIN"
  XCODEGEN="$LOCAL_BIN"
fi

"$XCODEGEN" generate
open TerminalAsset.xcodeproj
echo "Opened TerminalAsset.xcodeproj. Choose the TerminalAsset scheme and an iPhone Simulator, then press Run."
