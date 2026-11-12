#!/bin/bash
# Builds Gitzy in Release and packs it into Gitzy.dmg.
# Run it from the project root (the folder with Gitzy.xcodeproj):   ./make-dmg.sh
#
# No Apple Developer account needed. The app is signed "ad hoc" (CODE_SIGN_IDENTITY=-),
# which is what "Sign to Run Locally" does. It is NOT notarized, so on other Macs the first
# launch needs "Open Anyway" (see the README).
set -euo pipefail

APP_NAME="Gitzy"
PROJECT="Gitzy.xcodeproj"   # change this if your project file is named differently
SCHEME="Gitzy"

cd "$(dirname "$0")"
rm -rf build dist "$APP_NAME.dmg"

echo "Building (Release)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" \
    DEVELOPMENT_TEAM="" \
    build

APP="build/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP" ]; then
    echo "Could not find $APP. Check PROJECT and SCHEME at the top of this script."
    exit 1
fi

echo "Checking the signature..."
codesign --verify --deep --strict "$APP"

echo "Making the dmg..."
mkdir dist
cp -R "$APP" dist/
ln -s /Applications dist/Applications   # so people can drag the app onto it
hdiutil create -volname "$APP_NAME" -srcfolder dist -ov -format UDZO "$APP_NAME.dmg"

rm -rf dist
echo
echo "Done: $APP_NAME.dmg ($(du -h "$APP_NAME.dmg" | cut -f1))"
