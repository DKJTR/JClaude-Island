#!/bin/bash
# Build Claude Island for release
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/ClaudeIsland.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

echo "=== Building Claude Island ==="
echo ""

# Clean previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$PROJECT_DIR"

# Build and archive — pipe to xcpretty when available, but capture the real
# xcodebuild exit code so a noisy-but-successful xcpretty doesn't fail the build.
echo "Archiving..."
set +e
xcodebuild archive \
    -scheme ClaudeIsland \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_STYLE=Automatic \
    2>&1 | xcpretty
ARCHIVE_EXIT=${PIPESTATUS[0]}
set -e

if [ "$ARCHIVE_EXIT" -ne 0 ]; then
    echo "ERROR: Archive failed. Re-running with full output..."
    xcodebuild archive \
        -scheme ClaudeIsland \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        ENABLE_HARDENED_RUNTIME=YES \
        CODE_SIGN_STYLE=Automatic
    exit 1
fi

# Create ExportOptions.plist if it doesn't exist
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

# Export the archive
echo ""
echo "Exporting..."
set +e
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    2>&1 | xcpretty
EXPORT_EXIT=${PIPESTATUS[0]}
set -e

if [ "$EXPORT_EXIT" -ne 0 ]; then
    echo "ERROR: Export failed. Re-running with full output..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS"
    exit 1
fi

echo ""

# ============================================
# Step: Verify & repair entitlements
# ============================================
# xcodebuild silently drops CODE_SIGN_ENTITLEMENTS when signing identity is "-"
# (ad-hoc). Without the automation.apple-events entitlement, media controls
# silently fail on macOS — no prompt, no error, just dead play/pause buttons.
# Re-sign in place to embed them, then hard-fail if still missing.
echo "=== Verifying entitlements ==="
APP_PATH="$(/bin/ls -d "$EXPORT_PATH"/*.app 2>/dev/null | head -1)"
if [ -z "$APP_PATH" ]; then
    echo "ERROR: No .app found in $EXPORT_PATH"
    exit 1
fi
ENTITLEMENTS="$PROJECT_DIR/ClaudeIsland/Resources/ClaudeIsland.entitlements"
if ! codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null | grep -q "automation.apple-events"; then
    echo "Entitlements missing after xcodebuild (ad-hoc bug). Re-signing with $ENTITLEMENTS..."
    codesign -f -s - --entitlements "$ENTITLEMENTS" "$APP_PATH"
fi
if ! codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null | grep -q "automation.apple-events"; then
    echo "ERROR: automation.apple-events still missing after re-sign."
    echo "Media controls will not work. Refusing to ship this build."
    exit 1
fi
echo "OK: automation.apple-events entitlement embedded."
echo ""
echo "=== Build Complete ==="
echo "App exported to: $APP_PATH"
echo ""
echo "Next: Run ./scripts/create-release.sh to notarize and create DMG"
