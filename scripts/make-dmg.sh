#!/bin/zsh
# Builds a distribution DMG: build/dist/dotbar-<version>.dmg — Developer ID signed,
# notarized and stapled when the notary keychain profile exists. Same pipeline as
# usagebar and diskled-plus (shared "diskledplus-notary" profile, same Apple ID).
#
# Usage: scripts/make-dmg.sh   (version comes from CHANGELOG's top heading; VERSION and SIGN_IDENTITY override)
set -euo pipefail
NOTARY_PROFILE="diskledplus-notary"
STAGING="build/dmg-staging"
cd "${0:A:h:h}"

VERSION="${VERSION:-$(grep -m1 -oE '^## [0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md | sed 's/^## //')}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Marco Dal Moro (NGPL7S3YX3)}"
DMG="build/dist/dotbar-${VERSION}.dmg"

SIGN_IDENTITY="$SIGN_IDENTITY" ./scripts/build-app.sh

rm -rf "$STAGING"
mkdir -p "$STAGING" build/dist
cp -R build/dotbar.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "dotbar" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

# The DMG container itself is notarized (Apple best practice).
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

set +e
SUBMIT_OUTPUT="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
SUBMIT_STATUS=$?
set -e
if [ $SUBMIT_STATUS -eq 0 ]; then
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo "Notarized + stapled: $DMG"
elif echo "$SUBMIT_OUTPUT" | grep -qi "keychain\|credential"; then
  echo "WARNING: notary keychain profile '$NOTARY_PROFILE' not found."
  echo "DMG built but NOT notarized: $DMG"
  echo "Gatekeeper will block this on machines other than the build host."
  echo "Run: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <your Apple ID> --password <app-specific password> --team-id <TEAMID>"
else
  echo "Notarization submit failed:"
  echo "$SUBMIT_OUTPUT"
  exit 1
fi
