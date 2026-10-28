#!/bin/zsh
# Builds a universal Release Pixtamer.app and packages it as a drag-to-Applications DMG.
#
#   scripts/make-dmg.sh                          → dist/Pixtamer-<version>.dmg
#   NOTARY_PROFILE=<profile> scripts/make-dmg.sh → signed, notarized and stapled
#
# With a "Developer ID Application" certificate in the keychain, the app and DMG are signed with it,
# then notarized when NOTARY_PROFILE names a profile saved with `xcrun notarytool store-credentials`
# (skip with NOTARIZE=0). Without one, the app is ad-hoc signed and only opens freely on the Mac
# that built it.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DERIVED="$ROOT/build/ReleaseDerivedData"
DIST="$ROOT/dist"
cd "$ROOT"

IDENTITY="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"' || true)"
SIGNING=()
if [[ -n "$IDENTITY" ]]; then
  TEAM=$(echo "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')
  SIGNING=(CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" OTHER_CODE_SIGN_FLAGS=--timestamp)
  echo "▸ Signing with $IDENTITY"
else
  echo "▸ No Developer ID certificate found: building ad-hoc signed"
fi

echo "▸ Building Release (arm64 + x86_64)…"
xcodebuild -project Pixtamer.xcodeproj -scheme Pixtamer -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  ONLY_ACTIVE_ARCH=NO "${SIGNING[@]}" build -quiet

APP="$DERIVED/Build/Products/Release/Pixtamer.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")

echo "▸ Verifying signature…"
codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/Pixtamer"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Pixtamer.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$DIST"
DMG="$DIST/Pixtamer-$VERSION.dmg"
echo "▸ Creating $DMG…"
hdiutil create -volname "Pixtamer $VERSION" -srcfolder "$STAGE" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 -ov "$DMG" -quiet
hdiutil verify "$DMG" -quiet

PROFILE="${NOTARY_PROFILE:-}"
if [[ -n "$IDENTITY" ]]; then
  codesign --timestamp --sign "$IDENTITY" "$DMG"
  if [[ -n "$PROFILE" && "${NOTARIZE:-1}" == 1 ]]; then
    echo "▸ Notarizing (profile: $PROFILE)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
  fi
fi

echo "▸ Done"
ls -lh "$DMG"
shasum -a 256 "$DMG"
