#!/usr/bin/env bash
# Build DualCam OxO for the iOS Simulator, install it and launch with any args.
# Usage:
#   ./build-run.sh                      # build + launch on default device
#   ./build-run.sh -demoLang fr         # force UI language
#   ./build-run.sh -forceReview         # show the 24h review prompt immediately
#   DC_DEVICE="iPhone 16 Pro" ./build-run.sh
#
# NOTE: multi-cam capture only works on a real device. In the Simulator the app
# runs with placeholder feeds so the UI, settings, language and review flow are
# all testable.
set -euo pipefail

DEV="${DC_DEVICE:-iPhone 17 Pro}"
PROJ="$(cd "$(dirname "$0")" && pwd)"
APP="$PROJ/build/Debug-iphonesimulator/DualCamOXO.app"

echo "▶︎ Building…"
xcodebuild -project "$PROJ/DualCamOXO.xcodeproj" -target DualCamOXO \
  -sdk iphonesimulator -configuration Debug \
  CODE_SIGNING_ALLOWED=NO SYMROOT="$PROJ/build" build \
  | grep -E "error:|warning: [A-Z]|BUILD (SUCCEEDED|FAILED)" || true

echo "▶︎ Booting $DEV…"
xcrun simctl boot "$DEV" 2>/dev/null || true
xcrun simctl bootstatus "$DEV" >/dev/null 2>&1 || true
open -a Simulator || true

echo "▶︎ Installing…"
xcrun simctl install "$DEV" "$APP"
xcrun simctl terminate "$DEV" company.lno.dualcamoxo 2>/dev/null || true

echo "▶︎ Launching with: $*"
xcrun simctl launch "$DEV" company.lno.dualcamoxo "$@"
