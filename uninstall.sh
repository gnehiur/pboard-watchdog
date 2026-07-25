#!/bin/bash
# Removes pboard-watchdog completely.
set -u
LABEL="com.pboard-watchdog"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Library/Application Support/pboard-watchdog"
echo "pboard-watchdog uninstalled. (Log kept at ~/Library/Logs/pboard-watchdog.log — delete it manually if you want.)"
