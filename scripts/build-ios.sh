#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$TASK_ROOT/scripts/ios-toolchain.sh"
xcodebuild -project "$TASK_ROOT/iOS/Shiqi.xcodeproj" -scheme "Shiqi iOS" \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$TASK_ROOT/dist/ios-derived-data" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES build
echo "Simulator app: $TASK_ROOT/dist/ios-derived-data/Build/Products/Debug-iphonesimulator/Shiqi.app"
