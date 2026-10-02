#!/bin/bash
# Stops fanlined (it hands the fans back to macOS on SIGTERM) and removes it. Run as root.
set -uo pipefail
LABEL=com.joymadhu.fanlined
launchctl bootout "system/$LABEL" 2>/dev/null
rm -f "/Library/LaunchDaemons/$LABEL.plist" "/Library/PrivilegedHelperTools/$LABEL"
rm -f "/Library/Application Support/Fanline/status.json"
exit 0
