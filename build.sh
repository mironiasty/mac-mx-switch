#!/bin/zsh
# Builds MacMXSwitch.app.
#   ./build.sh            dev build: ad-hoc signed, installed to ~/Applications
#   ./build.sh --release  unsigned release bundle in build/ (signed by release.sh)
set -e
cd "${0:A:h}"

NAME=MacMXSwitch
BUNDLE_ID=asia.miron.macmxswitch
MIN_MACOS=13.0
VERSION=$(<VERSION)
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
APP=build/$NAME.app

rm -rf build && mkdir -p $APP/Contents/MacOS
swiftc -O -target arm64-apple-macos$MIN_MACOS *.swift -o $APP/Contents/MacOS/$NAME
cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>$NAME talks to your Logitech keyboard over Bluetooth to change its Easy-Switch channel.</string>
</dict></plist>
EOF

if [[ $1 == --release ]]; then
  echo "Built unsigned $APP ($VERSION, build $BUILD_NUMBER)"
  exit 0
fi

codesign --force --sign - --identifier $BUNDLE_ID $APP
# Replace a running menu bar instance with the new build.
was_running=false
if pgrep -xq $NAME; then was_running=true; pkill -x $NAME; sleep 0.5; fi
mkdir -p ~/Applications
rm -rf ~/Applications/$NAME.app
cp -R $APP ~/Applications/
echo "Installed ~/Applications/$NAME.app"
if $was_running; then open ~/Applications/$NAME.app && echo "Restarted $NAME"; fi
