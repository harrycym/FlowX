#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NimbusGlide"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

# Get version from argument or prompt
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh <version>"
    echo "Example: ./release.sh 1.0.2"
    exit 1
fi

NOTES="${2:-New release}"

echo "==> Building NimbusGlide v$VERSION..."

# Update version in Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$SCRIPT_DIR/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$SCRIPT_DIR/Resources/Info.plist"

# Update version in UpdateChecker.swift
sed -i '' "s/static let currentVersion = \".*\"/static let currentVersion = \"$VERSION\"/" "$SCRIPT_DIR/Sources/NimbusGlide/UpdateChecker.swift"

# Build
cd "$SCRIPT_DIR"
swift build -c release 2>&1

# Generate icon
ICON_PATH="$SCRIPT_DIR/Resources/AppIcon.icns"
swift "$SCRIPT_DIR/Scripts/generate_icon.swift" "$ICON_PATH" 2>/dev/null || true

# Assemble .app bundle
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$SCRIPT_DIR/.build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

if [ -f "$SCRIPT_DIR/Resources/Secrets.plist" ]; then
    cp "$SCRIPT_DIR/Resources/Secrets.plist" "$APP_BUNDLE/Contents/Resources/Secrets.plist"
fi

# Copy Sparkle framework into the bundle
SPARKLE_PATH=$(find "$SCRIPT_DIR/.build" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
if [ -n "$SPARKLE_PATH" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    cp -R "$SPARKLE_PATH" "$APP_BUNDLE/Contents/Frameworks/"
    echo "==> Bundled Sparkle.framework"
fi

# Set rpath so the binary finds Sparkle.framework in Contents/Frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# Sign
SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "NimbusGlide Dev" | head -1 | awk -F'"' '{print $2}')
if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$SCRIPT_DIR/$APP_NAME.entitlements" "$APP_BUNDLE"
    echo "==> Signed with $SIGN_IDENTITY"
else
    codesign --force --deep --sign - --entitlements "$SCRIPT_DIR/$APP_NAME.entitlements" "$APP_BUNDLE"
    echo "==> Signed ad-hoc"
fi

# Create zip for distribution
ZIP_PATH="$SCRIPT_DIR/NimbusGlide.zip"
rm -f "$ZIP_PATH"
cd "$SCRIPT_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
echo "==> Created $ZIP_PATH ($ZIP_SIZE bytes)"

# Sign the zip with Sparkle's EdDSA key (key is in macOS Keychain)
SIGN_TOOL=$(find "$SCRIPT_DIR/.build" -name "sign_update" -type f 2>/dev/null | head -1)
ED_SIGNATURE=""
if [ -n "$SIGN_TOOL" ]; then
    ED_SIGNATURE=$("$SIGN_TOOL" "$ZIP_PATH" 2>/dev/null | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//' || true)
    if [ -n "$ED_SIGNATURE" ]; then
        echo "==> Signed with EdDSA: ${ED_SIGNATURE:0:20}..."
    else
        echo "WARNING: Could not sign update. Sparkle will reject this update."
    fi
else
    echo "WARNING: sign_update tool not found. Sparkle will reject this update."
fi

# Update appcast.xml
PUBDATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')
cat > "$SCRIPT_DIR/appcast.xml" << APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>NimbusGlide Updates</title>
    <link>https://cdn.jsdelivr.net/gh/harrycym/NimbusGlide@main/appcast.xml</link>
    <description>NimbusGlide update feed</description>
    <language>en</language>
    <item>
      <title>NimbusGlide $VERSION</title>
      <description><![CDATA[<p>$NOTES</p>]]></description>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/harrycym/NimbusGlide/releases/download/v$VERSION/NimbusGlide.zip"
        length="$ZIP_SIZE"
        type="application/octet-stream"
        sparkle:edSignature="$ED_SIGNATURE"
      />
    </item>
  </channel>
</rss>
APPCAST
echo "==> Updated appcast.xml"

# Commit version bump + appcast
git add -A
git commit -m "Release v$VERSION: $NOTES" || true
git push origin main

# Create GitHub release with the zip
gh release create "v$VERSION" "$ZIP_PATH" \
    --title "NimbusGlide v$VERSION" \
    --notes "$NOTES"

echo ""
echo "==> Released NimbusGlide v$VERSION!"
echo "    GitHub: https://github.com/harrycym/NimbusGlide/releases/tag/v$VERSION"
echo "    Users will be notified automatically via Sparkle."
