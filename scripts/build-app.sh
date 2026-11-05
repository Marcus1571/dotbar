#!/bin/zsh
# Builds build/dotbar.app. Signs with the local "dotbar local signing" certificate when it exists in the login keychain
# (keeps the Accessibility grant across rebuilds), else ad hoc, in which case macOS forgets the grant on every rebuild. Pass --install to also copy it to ~/Applications and launch it.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" Sources/dotbar/*.swift -o build/dotbar
APP="build/dotbar.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp build/dotbar "$APP/Contents/MacOS/dotbar"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.dotbar</string>
  <key>CFBundleName</key><string>dotbar</string>
  <key>CFBundleExecutable</key><string>dotbar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.2</string>
  <key>CFBundleVersion</key><string>0.1.2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
IDENTITY="${SIGN_IDENTITY:-dotbar local signing}"
security find-identity -p codesigning | grep -q "\"$IDENTITY\"" || IDENTITY="-"
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP"
if [[ "${1:-}" == "--install" ]]; then
  pkill -x dotbar 2>/dev/null || true
  mkdir -p "$HOME/Applications"; rm -rf "$HOME/Applications/dotbar.app"
  cp -R "$APP" "$HOME/Applications/dotbar.app"
  open "$HOME/Applications/dotbar.app"
  echo "Installed and launched ~/Applications/dotbar.app"
fi
