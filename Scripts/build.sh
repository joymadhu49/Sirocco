#!/usr/bin/env bash
# Builds build/Fanline.app (menu bar app + fanlined helper inside it).
#
#   bash Scripts/build.sh            build only
#   bash Scripts/build.sh --install  build, put it in /Applications, (re)install the helper, run it
#
# Plain swiftc rather than an Xcode project: two small targets that share three files.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Fanline.app
INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true
SDK_FLAGS=(-O -target arm64-apple-macos14.0 -swift-version 5)

mkdir -p build
if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "==> rendering icon"
    swift Scripts/make_icon.swift
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

echo "==> fanlined"
swiftc "${SDK_FLAGS[@]}" Sources/Shared/*.swift Sources/Daemon/main.swift -o build/fanlined

echo "==> Fanline"
swiftc "${SDK_FLAGS[@]}" -parse-as-library Sources/Shared/*.swift Sources/App/*.swift -o build/Fanline

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Fanline build/fanlined "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns Resources/com.joymadhu.fanlined.plist Resources/*.sh "$APP/Contents/Resources/"

IDENTITY="${FANLINE_SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
        IDENTITY="Developer ID Application"
    else
        IDENTITY="-"
    fi
fi
echo "==> codesign ${IDENTITY}"
if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP/Contents/MacOS/fanlined"
    codesign --force --sign - "$APP"
else
    # Helper first: signing the bundle seals what is already inside it.
    codesign --force --options runtime --timestamp --identifier com.joymadhu.fanlined \
        --sign "$IDENTITY" "$APP/Contents/MacOS/fanlined"
    codesign --force --options runtime --timestamp --entitlements Fanline.entitlements \
        --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict --deep "$APP"
echo "==> built $APP"

if [[ "$INSTALL" == true ]]; then
    echo "==> installing to /Applications"
    pkill -x Fanline 2>/dev/null || true
    sleep 0.5
    rm -rf /Applications/Fanline.app
    cp -R "$APP" /Applications/
    echo "==> installing helper (sudo)"
    sudo bash /Applications/Fanline.app/Contents/Resources/install-helper.sh /Applications/Fanline.app "$USER"
    open -g /Applications/Fanline.app
    echo "==> Fanline is running"
fi
