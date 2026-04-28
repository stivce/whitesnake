#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Whitesnake"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/Build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT/Build/AppIcon.iconset"
ICON_SOURCE="$ROOT/whitesnake.png"
ICON_OUTPUT="$RESOURCES_DIR/AppIcon.icns"
EXECUTABLE_SOURCE="$BUILD_DIR/$APP_NAME"

swift build -c release --package-path "$ROOT"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

cp "$EXECUTABLE_SOURCE" "$MACOS_DIR/$APP_NAME"
cp "$ROOT/AppBundle/Info.plist" "$CONTENTS_DIR/Info.plist"

RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    DEST_BUNDLE="$RESOURCES_DIR/${APP_NAME}_${APP_NAME}.bundle"
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
    if [ ! -f "$DEST_BUNDLE/Info.plist" ]; then
        cat > "$DEST_BUNDLE/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.whitesnake.app.resources</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}_${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
EOF
    fi
fi

SPARKLE_FW=$(find "$ROOT/.build/artifacts" -name "Sparkle.framework" -path "*/macos-*" 2>/dev/null | head -1)
if [ -n "$SPARKLE_FW" ]; then
    mkdir -p "$CONTENTS_DIR/Frameworks"
    cp -R "$SPARKLE_FW" "$CONTENTS_DIR/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
fi

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICON_OUTPUT"

codesign --force --deep -s - "$APP_DIR"

touch "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
