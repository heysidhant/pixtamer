#!/bin/zsh
# Archives Pixtamer for the Mac App Store and exports a signed package.
#
#   scripts/make-appstore.sh                   → dist/AppStore/Pixtamer.pkg
#   UPLOAD=1 scripts/make-appstore.sh          → also uploads to App Store Connect
#
# Needs the Apple Developer account signed in to Xcode. Xcode creates the distribution certificates
# and provisioning profile on first use. The upload also needs the app record in App Store Connect.
# Increase the build number for every upload: BUILD_NUMBER=2 scripts/make-appstore.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEAM="${TEAM_ID:-RUCQNP5F6L}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DERIVED="$ROOT/build/AppStoreDerivedData"
ARCHIVE="$ROOT/build/Pixtamer.xcarchive"
OUT="$ROOT/dist/AppStore"
cd "$ROOT"

rm -rf "$ARCHIVE" "$OUT"
mkdir -p "$OUT"

echo "▸ Archiving Release (arm64 + x86_64), build $BUILD_NUMBER…"
xcodebuild -project Pixtamer.xcodeproj -scheme Pixtamer -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM="$TEAM" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='APP_STORE $(inherited)' \
  archive -quiet

echo "▸ Exporting signed package…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
  -exportOptionsPlist "$ROOT/Config/ExportOptions-AppStore.plist" \
  -allowProvisioningUpdates

PKG="$OUT/Pixtamer.pkg"
echo "▸ Package:"
ls -lh "$PKG"

if [[ "${UPLOAD:-0}" == 1 ]]; then
  echo "▸ Uploading to App Store Connect…"
  OPTIONS=$(mktemp -t ExportOptions)
  trap 'rm -f "$OPTIONS"' EXIT
  sed 's#<string>export</string>#<string>upload</string>#' "$ROOT/Config/ExportOptions-AppStore.plist" > "$OPTIONS"
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
    -exportOptionsPlist "$OPTIONS" -allowProvisioningUpdates
fi

echo "▸ Done"
