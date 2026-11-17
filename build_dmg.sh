#!/usr/bin/env bash
#
# build_dmg.sh - Build and package Mini Khmer Dictionary into a distributable .dmg
#
# Usage:
#   ./build_dmg.sh                  # Build Release and create DMG
#   ./build_dmg.sh --clean          # Clean build directory, then build DMG
#   ./build_dmg.sh --app path/to.app # Package existing .app bundle into DMG
#   ./build_dmg.sh --help           # Show all available options
#

set -euo pipefail

# ANSI color codes for friendly terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}${BOLD}==>${NC} ${BOLD}$1${NC}"
}

log_success() {
    echo -e "${GREEN}${BOLD}==>${NC} ${GREEN}$1${NC}"
}

log_warn() {
    echo -e "${YELLOW}${BOLD}==>${NC} ${YELLOW}$1${NC}"
}

log_error() {
    echo -e "${RED}${BOLD}==> ERROR:${NC} ${RED}$1${NC}" >&2
}

# Resolve root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT="$PROJECT_DIR/Mini Khmer Dictionary.xcodeproj"
SCHEME="Mini Khmer Dictionary"
APP_NAME="Mini Khmer Dictionary"
BUILD_DIR="$PROJECT_DIR/build"

# Default configuration values
CONFIGURATION="Release"
SIGN_IDENTITY="-"
CLEAN_BUILD=false
SKIP_DB=false
CUSTOM_APP_PATH=""
CUSTOM_OUTPUT=""

# Display usage
show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Builds the macOS application and packages it into a compressed .dmg disk image.

Options:
  -c, --config <type>       Build configuration: Release (default) or Debug
  -s, --sign <identity>     Code signing identity (default: "-" for local ad-hoc)
  -o, --output <file/dir>   Custom DMG output path or destination directory
      --app <path>          Package an already built .app bundle (skips build)
      --clean               Clean the build folder before compiling
      --skip-db             Skip rebuilding the dictionary SQLite database
  -h, --help                Show this help message and exit

Examples:
  ./build_dmg.sh
  ./build_dmg.sh --clean
  ./build_dmg.sh --sign "Developer ID Application: Your Name (TEAMID)"
  ./build_dmg.sh --app "build/Build/Products/Release/Mini Khmer Dictionary.app"
EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config|--configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        -s|--sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        -o|--output)
            CUSTOM_OUTPUT="$2"
            shift 2
            ;;
        --app)
            CUSTOM_APP_PATH="$2"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --skip-db)
            SKIP_DB=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            # Backward-compatibility: if positional argument ends with .app, treat as --app
            if [[ "$1" == *.app && -z "$CUSTOM_APP_PATH" ]]; then
                CUSTOM_APP_PATH="$1"
                shift
            else
                log_error "Unknown option: $1"
                show_help
                exit 1
            fi
            ;;
    esac
done

cd "$PROJECT_DIR"

APP_PATH="$CUSTOM_APP_PATH"

if [[ -z "$APP_PATH" ]]; then
    # Step 1: Clean build directory if requested
    if [[ "$CLEAN_BUILD" == true ]]; then
        log_info "Cleaning build directory..."
        rm -rf "$BUILD_DIR"
    fi

    # Step 2: Generate dictionary SQLite database if necessary
    DB_FILE="$PROJECT_DIR/Mini Khmer Dictionary/Resources/khmer_dict.sqlite3"
    if [[ "$SKIP_DB" == false ]]; then
        if [[ -f "Tools/build_dictionary_db.py" ]]; then
            log_info "Generating dictionary SQLite database..."
            python3 Tools/build_dictionary_db.py
        else
            log_warn "Tools/build_dictionary_db.py not found; skipping database generation."
        fi
    elif [[ ! -f "$DB_FILE" ]]; then
        log_warn "Dictionary database $DB_FILE does not exist. Consider running without --skip-db."
    fi

    # Step 3: Build the app using xcodebuild
    log_info "Building '$SCHEME' ($CONFIGURATION)..."

    BUILD_LOG="$(mktemp -t xcodebuild_dmg_XXXXXX.log)"
    trap 'rm -f "$BUILD_LOG"' EXIT

    XCODEBUILD_ARGS=(
        -project "$PROJECT"
        -scheme "$SCHEME"
        -configuration "$CONFIGURATION"
        -destination "platform=macOS"
        -derivedDataPath "$BUILD_DIR"
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGNING_ALLOWED=YES
    )
    # Don't override CODE_SIGN_ENTITLEMENTS: the app and the widget get their
    # entitlements (App Sandbox, network) from the project's build settings,
    # and macOS refuses to run a widget extension that isn't sandboxed.

    if ! xcodebuild build "${XCODEBUILD_ARGS[@]}" > "$BUILD_LOG" 2>&1; then
        log_error "Build failed! See log details below:"
        echo "--------------------------------------------------" >&2
        tail -n 60 "$BUILD_LOG" >&2
        echo "--------------------------------------------------" >&2
        log_error "Full build log available at: $BUILD_LOG"
        # Prevent immediate removal by trap so user can inspect if desired
        trap - EXIT
        exit 1
    fi
    rm -f "$BUILD_LOG"

    APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
fi

# Verify the built .app exists
if [[ ! -d "$APP_PATH" ]]; then
    log_error "App bundle not found at '$APP_PATH'"
    exit 1
fi

log_success "Found app bundle: $APP_PATH"

# Extract Version and Build Number from Info.plist
INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION="1.0"
BUILD_NUM=""
if [[ -f "$INFO_PLIST" ]]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || echo "1.0")"
    BUILD_NUM="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || echo "")"
fi

# Determine DMG output path
SAFE_APP_NAME="${APP_NAME// /-}"
DEFAULT_DMG_NAME="${SAFE_APP_NAME}-${VERSION}.dmg"

if [[ -n "$CUSTOM_OUTPUT" ]]; then
    if [[ -d "$CUSTOM_OUTPUT" ]]; then
        DMG_PATH="$CUSTOM_OUTPUT/$DEFAULT_DMG_NAME"
    else
        DMG_PATH="$CUSTOM_OUTPUT"
    fi
else
    DMG_PATH="$PROJECT_DIR/$DEFAULT_DMG_NAME"
fi

# Step 4: Code sign.
#
# xcodebuild has already signed the app and the widget with their
# entitlements. Re-signing is only needed for an identity other than ad-hoc
# or for an --app bundle that isn't signed yet, and then it goes inside out —
# widget first, app last — keeping each part's entitlements. (A plain
# `codesign --force --deep` replaces the signatures *and drops the
# entitlements*, which leaves a widget macOS won't load.)
sign_part() {
    local part="$1"
    local flags=(--force --sign "$SIGN_IDENTITY" --preserve-metadata=entitlements,requirements,flags)
    if [[ "$SIGN_IDENTITY" != "-" ]]; then
        flags+=(--options runtime --timestamp)
    fi
    codesign "${flags[@]}" "$part"
}

NEEDS_SIGNING=false
if ! codesign --verify --strict "$APP_PATH" >/dev/null 2>&1; then
    NEEDS_SIGNING=true
elif [[ "$SIGN_IDENTITY" != "-" ]] && ! codesign -dv "$APP_PATH" 2>&1 | grep -q "Authority=$SIGN_IDENTITY"; then
    NEEDS_SIGNING=true
fi

if [[ "$NEEDS_SIGNING" == true ]]; then
    log_info "Signing app bundle with identity: '$SIGN_IDENTITY'..."
    if [[ -d "$APP_PATH/Contents/PlugIns" ]]; then
        for extension in "$APP_PATH/Contents/PlugIns/"*.appex; do
            [[ -e "$extension" ]] && sign_part "$extension"
        done
    fi
    sign_part "$APP_PATH"
else
    log_info "Keeping the signature xcodebuild made ($SIGN_IDENTITY)"
fi

# Step 4b: Check the result before packaging. A widget without App Sandbox
# never shows up in the widget gallery, so stop here rather than ship one.
if ! codesign --verify --deep --strict "$APP_PATH"; then
    log_error "The app's signature doesn't verify."
    exit 1
fi
for extension in "$APP_PATH/Contents/PlugIns/"*.appex; do
    [[ -e "$extension" ]] || continue
    if ! codesign -d --entitlements - --xml "$extension" 2>/dev/null | grep -q "com.apple.security.app-sandbox"; then
        log_error "$(basename "$extension") isn't sandboxed, so macOS won't load the widget. Rebuild with --clean."
        exit 1
    fi
    log_success "$(basename "$extension") is signed and sandboxed"
done

# Step 5: Stage DMG contents
STAGING="$(mktemp -d -t dmg_staging_XXXXXX)"
# Ensure staging directory is cleaned up upon exit or interruption
trap 'rm -rf "$STAGING"' EXIT INT TERM

log_info "Staging DMG contents..."
ditto "$APP_PATH" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

# Step 6: Create the .dmg image
log_info "Creating disk image: $(basename "$DMG_PATH")..."
rm -f "$DMG_PATH"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH" \
    >/dev/null

# Final summary
DMG_SIZE="$(du -h "$DMG_PATH" | cut -f1 | xargs)"
DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"

echo ""
log_success "DMG successfully created!"
echo -e "  ${BOLD}Path:${NC}    $DMG_PATH"
echo -e "  ${BOLD}Size:${NC}    $DMG_SIZE"
echo -e "  ${BOLD}Version:${NC} $VERSION ${BUILD_NUM:+(Build $BUILD_NUM)}"
echo -e "  ${BOLD}SHA256:${NC}  $DMG_SHA256"
echo ""
