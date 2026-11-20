#!/bin/zsh
# Builds MacMXSwitch.app (ad-hoc signed) and installs it to ~/Applications.
set -e
cd "${0:A:h}"
APP=build/MacMXSwitch.app
rm -rf build && mkdir -p $APP/Contents/MacOS
swiftc -O main.swift DDC.swift -o $APP/Contents/MacOS/MacMXSwitch
cat > $APP/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>asia.miron.macmxswitch</string>
  <key>CFBundleName</key><string>MacMXSwitch</string>
  <key>CFBundleExecutable</key><string>MacMXSwitch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>MacMXSwitch talks to your Logitech keyboard over Bluetooth to change its Easy-Switch channel.</string>
</dict></plist>
EOF
codesign --force --sign - --identifier asia.miron.macmxswitch $APP
mkdir -p ~/Applications
rm -rf ~/Applications/MacMXSwitch.app
cp -R $APP ~/Applications/
echo "Installed ~/Applications/MacMXSwitch.app"
