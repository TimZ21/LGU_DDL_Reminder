#!/bin/bash
# Create a release ZIP only after Developer ID signing, notarization, stapling,
# and Gatekeeper verification all succeed. Authentication stays in Keychain.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$TASK_ROOT/scripts/macos-signing.sh"
TASK_SIGNING_IDENTITY="$(ddl_developer_id_hash "${DDL_SIGNING_IDENTITY:-}")"
if [ -z "${DDL_NOTARY_PROFILE:-}" ]; then
  echo "Set DDL_NOTARY_PROFILE to the profile stored with notarytool store-credentials." >&2
  exit 1
fi
TASK_NOTARY_DEVELOPER_DIR="${DDL_NOTARY_DEVELOPER_DIR:-${DDL_XCODE_PATH:-/Applications/Xcode.app}/Contents/Developer}"
notary_xcrun() { DEVELOPER_DIR="$TASK_NOTARY_DEVELOPER_DIR" xcrun "$@"; }
notary_xcrun notarytool --version
# Validate credentials before building or uploading software.
notary_xcrun notarytool history --keychain-profile "$DDL_NOTARY_PROFILE" --output-format json > /dev/null
cd "$TASK_ROOT"
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit the release source first so the archive can be traced to an exact clean commit." >&2
  exit 1
fi
TASK_SOURCE_COMMIT="$(git rev-parse HEAD)"
TASK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TASK_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
TASK_ARCH="$(uname -m)"
mkdir -p "$TASK_ROOT/dist"
TASK_RELEASE_WORK="$(mktemp -d "$TASK_ROOT/dist/macos-notary.XXXXXX")"
echo "Release work directory: $TASK_RELEASE_WORK"
bash scripts/test.sh
DDL_SIGNING_IDENTITY="$TASK_SIGNING_IDENTITY" bash scripts/build.sh
TASK_APP="$TASK_RELEASE_WORK/拾期.app"
ditto "$TASK_ROOT/dist/拾期.app" "$TASK_APP"
codesign --verify --deep --strict --verbose=2 "$TASK_APP"
ditto -c -k --keepParent "$TASK_APP" "$TASK_RELEASE_WORK/submission.zip"
notary_xcrun notarytool submit "$TASK_RELEASE_WORK/submission.zip" \
  --keychain-profile "$DDL_NOTARY_PROFILE" --output-format json > "$TASK_RELEASE_WORK/submission.json"
TASK_SUBMISSION_ID="$(plutil -extract id raw -o - "$TASK_RELEASE_WORK/submission.json")"
echo "Apple notarization submission: $TASK_SUBMISSION_ID"
if ! notary_xcrun notarytool wait "$TASK_SUBMISSION_ID" \
  --keychain-profile "$DDL_NOTARY_PROFILE" --timeout 20m --output-format json \
  > "$TASK_RELEASE_WORK/result.json"; then
  notary_xcrun notarytool log "$TASK_SUBMISSION_ID" --keychain-profile "$DDL_NOTARY_PROFILE" \
    "$TASK_RELEASE_WORK/notary-log.json" || true
  echo "Notarization did not finish successfully. Inspect $TASK_RELEASE_WORK; no release ZIP was created." >&2
  exit 1
fi
TASK_NOTARY_STATUS="$(plutil -extract status raw -o - "$TASK_RELEASE_WORK/result.json")"
if [ "$TASK_NOTARY_STATUS" != "Accepted" ]; then
  notary_xcrun notarytool log "$TASK_SUBMISSION_ID" --keychain-profile "$DDL_NOTARY_PROFILE" \
    "$TASK_RELEASE_WORK/notary-log.json" || true
  echo "Apple notarization status: $TASK_NOTARY_STATUS. No release ZIP was created." >&2
  exit 1
fi
notary_xcrun stapler staple "$TASK_APP"
notary_xcrun stapler validate "$TASK_APP"
codesign --verify --deep --strict --verbose=2 "$TASK_APP"
spctl --assess --type execute --verbose=2 "$TASK_APP"
# Only now create the public ZIP, from the app with its stapled ticket.
TASK_ZIP_NAME="Shiqi-$TASK_VERSION-macOS-$TASK_ARCH.zip"
TASK_FINAL_ZIP="$TASK_RELEASE_WORK/$TASK_ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$TASK_APP" "$TASK_FINAL_ZIP"
# Check the actual archive after extraction, not just the pre-packaged app.
mkdir -p "$TASK_RELEASE_WORK/extracted"
ditto -x -k "$TASK_FINAL_ZIP" "$TASK_RELEASE_WORK/extracted"
notary_xcrun stapler validate "$TASK_RELEASE_WORK/extracted/拾期.app"
codesign --verify --deep --strict --verbose=2 "$TASK_RELEASE_WORK/extracted/拾期.app"
spctl --assess --type execute --verbose=2 "$TASK_RELEASE_WORK/extracted/拾期.app"
TASK_RELEASE_DIR="$TASK_ROOT/dist/releases/$TASK_VERSION"
mkdir -p "$TASK_RELEASE_DIR"
mv "$TASK_FINAL_ZIP" "$TASK_RELEASE_DIR/$TASK_ZIP_NAME"
TASK_FINAL_ZIP="$TASK_RELEASE_DIR/$TASK_ZIP_NAME"
(
  cd "$TASK_RELEASE_DIR"
  shasum -a 256 "$TASK_ZIP_NAME" > SHA256SUMS.txt
)
cat > "$TASK_RELEASE_DIR/BUILD-INFO.txt" <<EOF
Version: $TASK_VERSION
Build: $TASK_BUILD
Architecture: $TASK_ARCH
Minimum macOS: 13.0
Source commit: $TASK_SOURCE_COMMIT
Signature: Developer ID Application
Signing identity hash: $TASK_SIGNING_IDENTITY
Notarization: Accepted
Submission ID: $TASK_SUBMISSION_ID
Stapled ticket: validated on extracted release app
Gatekeeper assessment: accepted on extracted release app
EOF
echo "Signed, notarized release: $TASK_FINAL_ZIP"
echo "Upload this ZIP, SHA256SUMS.txt, and BUILD-INFO.txt to the matching GitHub Release."
