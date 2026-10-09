#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_BUILD_ROOT="${TMPDIR:-/tmp}/ddlreminder-native-build"
TASK_ARCH="$(uname -m)"
source "$TASK_ROOT/scripts/toolchain.sh"
APP_PATH="$TASK_ROOT/dist/拾期.app"
# Recreate generated resources so removed assets cannot remain in a release bundle.
rm -rf "$APP_PATH/Contents/Resources"
mkdir -p "$TASK_BUILD_ROOT/module-cache" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cd "$TASK_ROOT"
xcrun swiftc -sdk "$TASK_SDK_PATH" -swift-version 5 -O -target "$TASK_ARCH-apple-macosx13.0" \
  -module-cache-path "$TASK_BUILD_ROOT/module-cache" -parse-as-library \
  -emit-module -emit-library -static -module-name DeadlineCore \
  Sources/DeadlineCore/*.swift -o "$TASK_BUILD_ROOT/libDeadlineCore.a" \
  -emit-module-path "$TASK_BUILD_ROOT/DeadlineCore.swiftmodule"
xcrun swiftc -sdk "$TASK_SDK_PATH" -swift-version 5 -O -target "$TASK_ARCH-apple-macosx13.0" \
  -module-cache-path "$TASK_BUILD_ROOT/module-cache" -parse-as-library \
  -I "$TASK_BUILD_ROOT" -L "$TASK_BUILD_ROOT" -lDeadlineCore \
  Sources/DDLReminder/*.swift -o "$APP_PATH/Contents/MacOS/DDLReminder"
xcrun swiftc -sdk "$TASK_SDK_PATH" -module-cache-path "$TASK_BUILD_ROOT/module-cache" scripts/MakeIcon.swift -o "$TASK_BUILD_ROOT/MakeIcon"
"$TASK_BUILD_ROOT/MakeIcon" "$TASK_BUILD_ROOT/AppIcon.iconset" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
codesign --force --sign - --identifier cn.shuning.ddlreminder "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$TASK_ROOT/dist/拾期.zip"
echo "已生成：$APP_PATH ($TASK_ARCH)"
