#!/bin/bash
set -euo pipefail

SCHEME="jenkins-tray"
CONFIG="Release"
DERIVED_DATA="build/DerivedData"
SOURCE_APP="$DERIVED_DATA/Build/Products/$CONFIG/jenkins-tray.app"
DEST_DIR="build"
DEST_APP="$DEST_DIR/JenkinsTray.app"

xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  build >/tmp/create_bundle_build.log

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Error: built app not found at $SOURCE_APP"
  echo "Check /tmp/create_bundle_build.log for build output."
  exit 1
fi

rm -rf "$DEST_APP"
mkdir -p "$DEST_DIR"
cp -R "$SOURCE_APP" "$DEST_APP"

codesign --force --deep --sign - "$DEST_APP"

echo "App bundle copied to $DEST_APP"
