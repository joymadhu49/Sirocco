#!/usr/bin/env bash
# Build Sirocco.app into build/Sirocco.app.
#
#   bash Scripts/build.sh             build
#   bash Scripts/build.sh --install   build, then replace /Applications/Sirocco.app and open it
#
# The Xcode project is generated from project.yml, so this script owns the whole chain:
# icon -> xcodegen -> xcodebuild -> codesign. CI and the release steps run this same script.
#
# Signing is done here by hand rather than by xcodebuild (invoked with CODE_SIGNING_ALLOWED=NO)
# so one script works both with and without a certificate. Pick the mode with
# SIROCCO_SIGNING_IDENTITY:
#
#   "Developer ID Application"   hardened runtime + secure timestamp, notarization ready.
#                                The only mode in which fan control works: the helper accepts
#                                XPC connections only from an app signed by the team in
#                                Sources/Shared/Identity.swift, and the app trusts only a
#                                helper signed the same way.
#   "-"                          ad-hoc. Compiles and launches (readings work) but the helper
#                                refuses it. Enough for a CI compile check.
#
# Unset, the script uses Developer ID when that certificate is installed, ad-hoc otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Sirocco"
HELPER_NAME="SiroccoHelper"
HELPER_ID="com.joymadhu.sirocco.helper"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-build}"
APP_DIR="build/${APP_NAME}.app"
INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

# Deliberately an empty <dict>, and comment free (Apple's AMFI parser rejects XML comments).
# Sirocco needs no entitlement: reading the SMC needs none, and fan writes happen in the root
# helper. No App Sandbox, because a sandboxed app cannot register a launchd daemon, which is
# also why Sirocco ships outside the Mac App Store, Developer ID signed and notarized.
ENTITLEMENTS="${APP_NAME}.entitlements"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "ERROR: xcodegen not found. Install it with: brew install xcodegen" >&2
    exit 1
fi

if [[ ! -f "Resources/AppIcon.icns" ]]; then
    echo "==> Resources/AppIcon.icns missing, rendering it"
    bash Scripts/make-icon.sh
fi

echo "==> xcodegen generate"
xcodegen generate --quiet

echo "==> xcodebuild ($CONFIGURATION, unsigned; signed below)"
mkdir -p build
LOG="build/xcodebuild.log"
# Full log to a file, errors to the terminal. Piping xcodebuild into grep would hide its exit
# status, which is how a failed build gets signed anyway.
if ! xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" \
    build > "$LOG" 2>&1; then
    echo "ERROR: build failed" >&2
    grep -E "error:" "$LOG" | sort -u | head -40 >&2
    echo "(full log in $LOG)" >&2
    exit 1
fi

BUILT="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "$BUILT" ]]; then
    echo "ERROR: xcodebuild reported success but there is no bundle at $BUILT" >&2
    exit 1
fi

echo "==> staging ${APP_DIR}"
rm -rf "$APP_DIR"
cp -R "$BUILT" "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true

HELPER="${APP_DIR}/Contents/MacOS/${HELPER_NAME}"
DAEMON_PLIST="${APP_DIR}/Contents/Library/LaunchDaemons/${HELPER_ID}.plist"
for required in "$HELPER" "$DAEMON_PLIST"; do
    if [[ ! -e "$required" ]]; then
        echo "ERROR: $required is missing from the bundle; check the copy phases in project.yml" >&2
        exit 1
    fi
done

# Sparkle arrives from SwiftPM ad-hoc signed. Under the hardened runtime, library validation
# refuses a framework not signed by the app's team, and notarization rejects nested code
# without a Developer ID and timestamp. So it is signed again, innermost first (no --deep,
# which signs in the wrong order). Its XPC services serve sandboxed apps only and are dropped.
SPARKLE="${APP_DIR}/Contents/Frameworks/Sparkle.framework"
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"

sign_all() {
    local flags=("$@")
    codesign "${flags[@]}" "$SPARKLE/Versions/B/Autoupdate"
    codesign "${flags[@]}" "$SPARKLE/Versions/B/Updater.app"
    codesign "${flags[@]}" "$SPARKLE"
    # The helper's identifier is what the app's XPC code signing requirement names.
    codesign "${flags[@]}" --identifier "$HELPER_ID" "$HELPER"
    codesign "${flags[@]}" --entitlements "$ENTITLEMENTS" "$APP_DIR"
}

have_developer_id() {
    security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"
}

SIGNING_IDENTITY="${SIROCCO_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    if have_developer_id; then
        SIGNING_IDENTITY="Developer ID Application"
    else
        SIGNING_IDENTITY="-"
        echo "==> No Developer ID certificate in the keychain, falling back to ad-hoc signing."
    fi
fi

case "$SIGNING_IDENTITY" in
  "Developer ID"*)
    have_developer_id || { echo "ERROR: no 'Developer ID Application' certificate installed" >&2; exit 1; }
    echo "==> Signing with '$SIGNING_IDENTITY' (hardened runtime + secure timestamp)"
    sign_all --force --options runtime --timestamp --sign "$SIGNING_IDENTITY"
    codesign --verify --strict --deep --verbose=2 "$APP_DIR"
    ;;
  *)
    echo "==> Ad-hoc signing (compile check only; the helper will refuse this build)"
    sign_all --force --sign -
    ;;
esac

echo "==> Built $APP_DIR ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist"))"

if [[ "$INSTALL" == true ]]; then
    echo "==> Installing to /Applications"
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP_DIR" /Applications/
    open "/Applications/${APP_NAME}.app"
    echo "==> ${APP_NAME} is running"
fi
