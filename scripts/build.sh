#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift build -c release --disable-sandbox -Xswiftc -warnings-as-errors
APP="${1:-${PWD}/build/Afterglow.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Afterglow "$APP/Contents/MacOS/Afterglow"
cp resources/Info.plist "$APP/Contents/Info.plist"
cp resources/Afterglow.icns "$APP/Contents/Resources/Afterglow.icns"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
