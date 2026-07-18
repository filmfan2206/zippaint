#!/bin/bash
# Builds ZipPaint.app entirely inside this folder — no system installs,
# no PATH changes. Requires the Xcode / Swift toolchain already on the system.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ZipPaint"
BUNDLE_ID="local.zippaint"
VERSION="1.0"

swift build -c release

APP="$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force -s - "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1)) — run with: open $APP"
