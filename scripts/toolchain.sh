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

# Some Command Line Tools releases ship two module maps for SwiftBridging.
# Clang reads both and fails before compiling our sources. Hide the older map
# only for these compiler invocations; leave the installed toolchain untouched.
TASK_SWIFT_CC_FLAGS=()
TASK_SWIFT_INCLUDE="$TASK_DEVELOPER_DIR/usr/include/swift"
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
  TASK_SWIFT_CC_FLAGS=(-vfsoverlay "$TASK_BUILD_ROOT/sdk-overlay/overlay.yaml")
fi
