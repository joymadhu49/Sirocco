#!/usr/bin/env bash
# Renders Resources/AppIcon.icns and Resources/AppIcon.png from Scripts/make_icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swift Scripts/make_icon.swift
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
echo "==> Resources/AppIcon.icns"
