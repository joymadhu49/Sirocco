#!/bin/bash
# Installs (or reinstalls) fanlined as a root LaunchDaemon. Run as root:
#   install-helper.sh /path/to/Fanline.app <user who owns the settings>
set -euo pipefail
APP="$1"
OWNER="$2"
LABEL=com.joymadhu.fanlined
SUPPORT="/Library/Application Support/Fanline"

# The earlier always-on fanctl daemon would fight fanlined for the fans.
if [[ -f /Library/LaunchDaemons/com.joymadhu.fanctl.plist ]]; then
    launchctl bootout system/com.joymadhu.fanctl 2>/dev/null || true
    rm -f /Library/LaunchDaemons/com.joymadhu.fanctl.plist
fi

launchctl bootout "system/$LABEL" 2>/dev/null || true
install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools "$SUPPORT"
install -d -o "$OWNER" -g staff -m 755 "$SUPPORT/user"
install -o root -g wheel -m 755 "$APP/Contents/MacOS/fanlined" "/Library/PrivilegedHelperTools/$LABEL"
install -o root -g wheel -m 644 "$APP/Contents/Resources/$LABEL.plist" "/Library/LaunchDaemons/$LABEL.plist"
launchctl bootstrap system "/Library/LaunchDaemons/$LABEL.plist"
