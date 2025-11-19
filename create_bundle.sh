#!/bin/bash

APP_NAME="jenkins-tray"
BUNDLE_ID="com.camilomontoyau.jenkins-tray"
OUTPUT_DIR="$APP_NAME.app"
EXECUTABLE_NAME="jenkins-tray"

echo "🚀 Building Release version..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Build failed."
    exit 1
fi

echo "📂 Creating Bundle Structure..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/Contents/MacOS"
mkdir -p "$OUTPUT_DIR/Contents/Resources"

# Copy Executable
cp ".build/release/$EXECUTABLE_NAME" "$OUTPUT_DIR/Contents/MacOS/$APP_NAME"

# Create Info.plist
echo "📝 Creating Info.plist..."
cat > "$OUTPUT_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
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
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc Code Signing (Required for local execution on Apple Silicon)
echo "🔐 Signing the app..."
codesign --force --deep --sign - "$OUTPUT_DIR"

echo "✅ Done! Application created at ./$OUTPUT_DIR"
echo "👉 You can drag this to your Applications folder."

