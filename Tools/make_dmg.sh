#!/bin/bash
#
# Package the app into a distributable .dmg.
#
#   Tools/make_dmg.sh                 # build Release, then package
#   Tools/make_dmg.sh path/to/App.app # package an app that is already built
#
# The disk image contains the app plus a shortcut to /Applications, which is
# all the "drag me" window most Mac users expect.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$PROJECT_DIR/Mini Khmer Dictionary.xcodeproj"
SCHEME="Mini Khmer Dictionary"
APP_NAME="Mini Khmer Dictionary"

cd "$PROJECT_DIR"

APP_PATH="${1:-}"

if [[ -z "$APP_PATH" ]]; then
    echo "==> Generating the dictionary database"
    python3 Tools/build_dictionary_db.py

    echo "==> Building $SCHEME (Release)"
    xcodebuild build \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$PROJECT_DIR/build" \
        >/dev/null

    APP_PATH="$PROJECT_DIR/build/Build/Products/Release/$APP_NAME.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: no app bundle at $APP_PATH" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG_PATH="$PROJECT_DIR/${APP_NAME// /-}-$VERSION.dmg"

# An unsigned bundle will not launch at all on Apple Silicon, so make sure the
# app carries at least an ad-hoc signature before it goes into the image.
if ! codesign --display "$APP_PATH" >/dev/null 2>&1; then
    echo "==> Ad-hoc signing (the bundle is unsigned)"
    codesign --force --deep --sign - "$APP_PATH"
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "==> Staging"
ditto "$APP_PATH" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

echo "==> Building disk image"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH" \
    >/dev/null

echo "==> Wrote $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
codesign --display --verbose=2 "$APP_PATH" 2>&1 | grep -E "^(Authority|Signature|TeamIdentifier)" || true
