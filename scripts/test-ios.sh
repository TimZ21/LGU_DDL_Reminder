#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$TASK_ROOT/scripts/ios-toolchain.sh"
if [ -z "${DDL_IOS_DESTINATION:-}" ]; then
  echo "Choose an installed simulator with: DEVELOPER_DIR=\"$DEVELOPER_DIR\" xcrun simctl list devices available"
  echo "Then run: DDL_IOS_DESTINATION='platform=iOS Simulator,id=<device-UUID>' bash scripts/test-ios.sh"
  exit 1
fi
xcodebuild -project "$TASK_ROOT/iOS/Shiqi.xcodeproj" -scheme "Shiqi iOS" \
  -configuration Debug -destination "$DDL_IOS_DESTINATION" \
  -derivedDataPath "$TASK_ROOT/dist/ios-derived-data" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES \
  -parallel-testing-enabled NO test
