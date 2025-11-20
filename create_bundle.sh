#!/bin/bash
set -euo pipefail

SCHEME="jenkins-tray"
APP_NAME="JenkinsTray"
BUNDLE_ID="com.camilomontoyau.jenkins-tray"
CONFIG="Release"
DERIVED_DATA="build/DerivedData"

xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  build >/tmp/create_bundle_build.log

APP_DIR="build/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

EXECUTABLE_PATH="$DERIVED_DATA/Build/Products/$CONFIG/jenkins-tray"
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "Error: expected executable not found at $EXECUTABLE_PATH"
  exit 1
fi

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Jenkins Tray</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF2

codesign --force --deep --sign - "$APP_DIR"

echo "App bundle created at $APP_DIR"
echo "Binary copied from $EXECUTABLE_PATH"
