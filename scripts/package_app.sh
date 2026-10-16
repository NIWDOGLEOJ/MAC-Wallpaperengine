#!/usr/bin/env bash
set -euo pipefail

# Package Wallpaper Engine into a standalone macOS .app bundle and distributable .dmg

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
APP_NAME="Wallpaper Engine"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_NAME="WallpaperEngine-v1.0.0.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$DIST_DIR/dmg_staging"

echo "==> 1. Building release binary with Swift Package Manager..."
cd "$REPO_ROOT"
swift build -c release --product WallpaperEngineApp

BIN_PATH="$REPO_ROOT/.build/out/Products/Release/WallpaperEngineApp"
if [ ! -f "$BIN_PATH" ]; then
    # Fallback path if out directory differs
    BIN_PATH="$REPO_ROOT/.build/release/WallpaperEngineApp"
fi

if [ ! -f "$BIN_PATH" ]; then
    echo "Error: Release binary not found at $BIN_PATH"
    exit 1
fi

echo "==> 2. Assembling macOS application bundle: $APP_BUNDLE..."
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/WallpaperEngineApp"
chmod +x "$APP_BUNDLE/Contents/MacOS/WallpaperEngineApp"

# Copy Info.plist
cp "$REPO_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Create PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy AppIcon.icns
if [ -f "$REPO_ROOT/Resources/AppIcon.icns" ]; then
    cp "$REPO_ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Copy ML models if present
if [ -d "$REPO_ROOT/Resources/Models" ]; then
    cp -R "$REPO_ROOT/Resources/Models" "$APP_BUNDLE/Contents/Resources/"
fi

echo "==> 3. Signing application bundle (Ad-Hoc codesign)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> 4. Preparing DMG staging directory..."
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> 5. Creating compressed disk image: $DMG_PATH..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "==> 6. Verifying disk image..."
hdiutil verify "$DMG_PATH"

echo "==> DMG generated successfully:"
ls -lh "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
