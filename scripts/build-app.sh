#!/bin/zsh
# Builds build/dotbar.app. Signs with $SIGN_IDENTITY when it exists in the login keychain (default: the local
# "dotbar local signing" certificate, which keeps the Accessibility grant across rebuilds); a Developer ID
# identity additionally gets the hardened runtime and a timestamp, which is what Apple notarization requires.
# Pass --install to also copy it to ~/Applications and launch it.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" Sources/dotbar/*.swift -o build/dotbar
APP="build/dotbar.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/dotbar "$APP/Contents/MacOS/dotbar"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Credits.rtf "$APP/Contents/Resources/Credits.rtf"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.dotbar</string>
  <key>CFBundleName</key><string>dotbar</string>
  <key>CFBundleDisplayName</key><string>dotbar</string>
  <key>CFBundleExecutable</key><string>dotbar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>0.3.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Marco Dal Moro</string>
</dict></plist>
PLIST
IDENTITY="${SIGN_IDENTITY:-dotbar local signing}"
security find-identity -p codesigning | grep -q "\"$IDENTITY\"" || IDENTITY="-"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
elif [[ "$IDENTITY" == "Developer ID"* ]]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  codesign --force --sign "$IDENTITY" "$APP"
fi
echo "Built $APP"
if [[ "${1:-}" == "--install" ]]; then
  pkill -x dotbar 2>/dev/null || true
  mkdir -p "$HOME/Applications"; rm -rf "$HOME/Applications/dotbar.app"
  cp -R "$APP" "$HOME/Applications/dotbar.app"
  open "$HOME/Applications/dotbar.app"
  echo "Installed and launched ~/Applications/dotbar.app"
fi
