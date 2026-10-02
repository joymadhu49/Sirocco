#!/usr/bin/env bash
# Build, notarize and package a release locally. Publishes NOTHING: it stops with the
# files ready and prints the command that would publish them.
#
#   bash Scripts/release.sh
#
# Needs a notarytool keychain profile (once per Mac):
#   xcrun notarytool store-credentials sirocco-notary \
#     --key ~/Downloads/AuthKey_<KEY_ID>.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
# Override the profile name with AC_KEYCHAIN_PROFILE.
#
# Steps: build (Developer ID) -> notarize + staple the app -> DMG around the stapled app
# -> notarize + staple the DMG -> sign the DMG for Sparkle and write build/appcast.xml.
set -euo pipefail
cd "$(dirname "$0")/.."

export AC_KEYCHAIN_PROFILE="${AC_KEYCHAIN_PROFILE:-sirocco-notary}"
export SIROCCO_SIGNING_IDENTITY="Developer ID Application"

if ! xcrun notarytool history --keychain-profile "$AC_KEYCHAIN_PROFILE" >/dev/null 2>&1; then
    echo "ERROR: notarytool profile '$AC_KEYCHAIN_PROFILE' is missing or invalid. See the header of this script." >&2
    exit 1
fi

bash Scripts/build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Sirocco.app/Contents/Info.plist)"
DMG="build/Sirocco-${VERSION}.dmg"

bash Scripts/notarize.sh build/Sirocco.app
bash Scripts/make-dmg.sh "$VERSION"
bash Scripts/notarize.sh "$DMG"
bash Scripts/make-appcast.sh "$DMG"

cat <<MSG

==> Release ${VERSION} is ready (not published):
      $DMG
      build/appcast.xml

    To publish, push the repo and run:
      gh release create v${VERSION} "$DMG" build/appcast.xml \\
        --title "Sirocco ${VERSION}" --notes-file <(sed -n '/^## ${VERSION}/,/^## /p' CHANGELOG.md | sed '\$d')
MSG
