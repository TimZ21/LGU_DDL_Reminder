#!/bin/bash
# Prefer the Command Line Tools' selected SDK symlink rather than xcrun's newest SDK.
# DDL_SDK_PATH allows an explicit SDK on machines with multiple toolchains.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
  # Xcode's first launch can change the global selection. Keep Mac scripts on
  # their existing compiler; an explicit DEVELOPER_DIR still takes precedence.
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
TASK_SDK_PATH="${DDL_SDK_PATH:-}"
if [ -z "$TASK_SDK_PATH" ]; then
  TASK_DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
  if [ -d "$TASK_DEVELOPER_DIR/SDKs/MacOSX.sdk" ]; then
    TASK_SDK_PATH="$TASK_DEVELOPER_DIR/SDKs/MacOSX.sdk"
  else
    TASK_SDK_PATH="$(xcrun --show-sdk-path)"
  fi
fi
