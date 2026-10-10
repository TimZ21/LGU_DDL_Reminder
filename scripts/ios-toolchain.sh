#!/bin/bash
# Use Xcode explicitly; leave the Mac's existing Command Line Tools selection intact.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  TASK_IOS_XCODE="${DDL_XCODE_PATH:-/Applications/Xcode.app}"
  export DEVELOPER_DIR="$TASK_IOS_XCODE/Contents/Developer"
fi
if [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
  echo "Install Xcode from the Mac App Store and complete first-launch setup."
  echo "For another location, set DDL_XCODE_PATH or DEVELOPER_DIR."
  exit 1
fi
