#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_BUILD_ROOT="${TMPDIR:-/tmp}/ddlreminder-native-tests"
source "$TASK_ROOT/scripts/toolchain.sh"
mkdir -p "$TASK_BUILD_ROOT/module-cache"
cd "$TASK_ROOT"
xcrun swiftc -sdk "$TASK_SDK_PATH" -swift-version 5 -module-cache-path "$TASK_BUILD_ROOT/module-cache" -parse-as-library \
  -emit-module -emit-library -static -module-name DeadlineCore \
  Sources/DeadlineCore/*.swift -o "$TASK_BUILD_ROOT/libDeadlineCore.a" \
  -emit-module-path "$TASK_BUILD_ROOT/DeadlineCore.swiftmodule"
xcrun swiftc -sdk "$TASK_SDK_PATH" -swift-version 5 -module-cache-path "$TASK_BUILD_ROOT/module-cache" \
  -I "$TASK_BUILD_ROOT" -L "$TASK_BUILD_ROOT" -lDeadlineCore \
  Tests/DeadlineCoreTests/*.swift scripts/TestRunner.swift -o "$TASK_BUILD_ROOT/CoreTests"
"$TASK_BUILD_ROOT/CoreTests"
