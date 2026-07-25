#!/bin/bash
# Installs pboard-watchdog for the current user (no sudo required):
#   1. compiles the pbprobe helper (needs Xcode Command Line Tools)
#   2. copies everything to ~/Library/Application Support/pboard-watchdog
#   3. registers a LaunchAgent so it starts at login and stays running
set -eu

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/Library/Application Support/pboard-watchdog"
PLIST="$HOME/Library/LaunchAgents/com.pboard-watchdog.plist"
LABEL="com.pboard-watchdog"

echo "==> Compiling pbprobe..."
mkdir -p "$SRC_DIR/bin"
swiftc -O -o "$SRC_DIR/bin/pbprobe" "$SRC_DIR/src/pbprobe.swift"

echo "==> Installing to $APP_DIR"
mkdir -p "$APP_DIR/bin" "$HOME/Library/LaunchAgents"
cp "$SRC_DIR/bin/pbprobe" "$APP_DIR/bin/pbprobe"
cp "$SRC_DIR/pboard-watchdog.sh" "$APP_DIR/pboard-watchdog.sh"
chmod +x "$APP_DIR/pboard-watchdog.sh" "$APP_DIR/bin/pbprobe"

echo "==> Registering LaunchAgent"
sed -e "s|__INSTALL_DIR__|$APP_DIR|g" -e "s|__HOME__|$HOME|g" \
    "$SRC_DIR/com.pboard-watchdog.plist" > "$PLIST"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "==> Done. Status:"
launchctl print "gui/$(id -u)/$LABEL" | grep -E "state|pid" | head -3
echo "Log: ~/Library/Logs/pboard-watchdog.log"
