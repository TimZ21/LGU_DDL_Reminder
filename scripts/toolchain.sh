#!/bin/bash
# Prefer the Command Line Tools' selected SDK symlink rather than xcrun's newest SDK.
# DDL_SDK_PATH allows an explicit SDK on machines with multiple toolchains.
TASK_SDK_PATH="${DDL_SDK_PATH:-}"
if [ -z "$TASK_SDK_PATH" ]; then
  TASK_DEVELOPER_DIR="$(xcode-select -p)"
  if [ -d "$TASK_DEVELOPER_DIR/SDKs/MacOSX.sdk" ]; then
    TASK_SDK_PATH="$TASK_DEVELOPER_DIR/SDKs/MacOSX.sdk"
  else
    TASK_SDK_PATH="$(xcrun --show-sdk-path)"
  fi
fi

# Some Command Line Tools releases ship two module maps for SwiftBridging.
# Clang reads both and fails before compiling our sources. Hide the older map
# only for these compiler invocations; leave the installed toolchain untouched.
TASK_SWIFT_CC_FLAGS=()
TASK_SWIFT_INCLUDE="$(xcode-select -p)/usr/include/swift"
if [ -f "$TASK_SWIFT_INCLUDE/module.modulemap" ] && [ -f "$TASK_SWIFT_INCLUDE/bridging.modulemap" ]; then
  mkdir -p "$TASK_BUILD_ROOT/sdk-overlay"
  printf '%s\n' '// Obsolete duplicate SwiftBridging module map hidden by VFS overlay.' > "$TASK_BUILD_ROOT/sdk-overlay/empty.modulemap"
  cat > "$TASK_BUILD_ROOT/sdk-overlay/overlay.yaml" <<EOF
{
  'version': 0,
  'case-sensitive': 'true',
  'roots': [
    { 'type': 'directory', 'name': '$TASK_SWIFT_INCLUDE',
      'contents': [
        { 'type': 'file', 'name': 'module.modulemap', 'external-contents': '$TASK_BUILD_ROOT/sdk-overlay/empty.modulemap' }
      ]
    }
  ]
}
EOF
  TASK_SWIFT_CC_FLAGS=(-Xcc -ivfsoverlay -Xcc "$TASK_BUILD_ROOT/sdk-overlay/overlay.yaml")
fi
