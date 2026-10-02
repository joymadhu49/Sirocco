#!/usr/bin/env bash
# Renders Resources/dmg-background.tiff (1x and 2x in one file, which is what Finder wants for
# a sharp background on Retina displays) from Scripts/make_dmg_background.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swift Scripts/make_dmg_background.swift
tiffutil -cathidpicheck build/dmg-background.png build/dmg-background@2x.png \
    -out Resources/dmg-background.tiff 2>/dev/null
echo "==> Resources/dmg-background.tiff"
