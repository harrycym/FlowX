#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NimbusGlide"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

echo "==> Building $APP_NAME..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

echo "==> Generating app icon..."
ICON_PATH="$SCRIPT_DIR/Resources/AppIcon.icns"
swift "$SCRIPT_DIR/Scripts/generate_icon.swift" "$ICON_PATH"

echo "==> Assembling $APP_NAME.app bundle..."

# Clean previous bundle
rm -rf "$APP_BUNDLE"

# Create directory structure
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Copy binary
cp "$SCRIPT_DIR/.build/release/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

# Copy Info.plist
cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"

# Copy icon
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$CONTENTS/Resources/AppIcon.icns"
fi

# Bundle Secrets.plist
if [ -f "$SCRIPT_DIR/Resources/Secrets.plist" ]; then
    cp "$SCRIPT_DIR/Resources/Secrets.plist" "$CONTENTS/Resources/Secrets.plist"
    echo "==> Bundled Secrets.plist"
fi

# Bundle Sparkle framework
SPARKLE_PATH=$(find "$SCRIPT_DIR/.build" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
if [ -n "$SPARKLE_PATH" ]; then
    mkdir -p "$CONTENTS/Frameworks"
    cp -R "$SPARKLE_PATH" "$CONTENTS/Frameworks/"
    echo "==> Bundled Sparkle.framework"
fi

# Set rpath so the binary finds Sparkle.framework in Contents/Frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/$APP_NAME" 2>/dev/null || true

# Copy entitlements and sign
if [ -f "$SCRIPT_DIR/$APP_NAME.entitlements" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "NimbusGlide Dev" | head -1 | awk -F'"' '{print $2}' || true)
    if [ -n "$SIGN_IDENTITY" ]; then
        codesign --force --sign "$SIGN_IDENTITY" --entitlements "$SCRIPT_DIR/$APP_NAME.entitlements" "$APP_BUNDLE"
        echo "==> Signed with $SIGN_IDENTITY (stable identity)"
    else
        codesign --force --sign - --entitlements "$SCRIPT_DIR/$APP_NAME.entitlements" "$APP_BUNDLE"
        echo "==> Signed ad-hoc"
    fi
fi

echo "==> Built: $APP_BUNDLE"
echo ""
echo "You can now:"
echo "  1. Double-click NimbusGlide.app to launch"
echo "  2. Drag it to /Applications"
echo "  3. Run: open \"$APP_BUNDLE\""
