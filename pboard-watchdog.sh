#!/bin/bash
# pboard-watchdog — detects a hung macOS pasteboard server and restarts it.
#
# Background: when Universal Clipboard fetches remote content from an
# iPhone/iPad and the peer-to-peer link dies mid-request, pboard can block
# for ~30 minutes with no sane timeout. Because the pasteboard is a single
# global service that most apps query synchronously on focus/menu updates,
# the whole GUI appears frozen until the fetch times out.
#
# This daemon probes pboard's liveness every INTERVAL seconds with pbprobe
# (a changeCount query — no clipboard content is read or written). After
# STRIKES consecutive timeouts it restarts pboard (launchd respawns it
# instantly, releasing every blocked app), escalating to SIGKILL and then
# to useractivityd if needed.
#
# Compatible with the stock macOS bash 3.2.

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
PROBE="$DIR/bin/pbprobe"
LOG="$HOME/Library/Logs/pboard-watchdog.log"
INTERVAL="${PBWD_INTERVAL:-30}"        # seconds between probes
PROBE_TIMEOUT="${PBWD_PROBE_TIMEOUT:-25}"  # seconds before a probe counts as hung
STRIKES="${PBWD_STRIKES:-2}"           # consecutive timeouts before acting
MAX_LOG_BYTES=1048576                  # 1 MB cap, then truncated

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

rotate_log() {
    local size
    size=$(stat -f%z "$LOG" 2>/dev/null || echo 0)
    if [ "$size" -gt "$MAX_LOG_BYTES" ]; then
        tail -c 262144 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
        log "log rotated"
    fi
}

notify() {
    /usr/bin/osascript -e "display notification \"$1\" with title \"pboard-watchdog\"" >/dev/null 2>&1
}

recover() {
    local t0 t1
    t0=$(date +%s)
    log "hang confirmed ($STRIKES consecutive probe timeouts) — sending SIGTERM to pboard"
    /usr/bin/killall pboard 2>/dev/null
    sleep 5
    if ! "$PROBE" 10; then
        log "pboard still unresponsive — sending SIGKILL"
        /usr/bin/killall -9 pboard 2>/dev/null
        sleep 5
    fi
    if ! "$PROBE" 10; then
        log "still unresponsive after SIGKILL — force-killing pboard again"
        /usr/bin/killall -9 pboard 2>/dev/null
        sleep 5
    fi
    # Always restart useractivityd after a pboard restart: its outbound
    # advertising state goes stale against the new pboard instance, which
    # silently breaks Mac -> iPhone/iPad clipboard sync (inbound keeps
    # working, making the breakage easy to miss).
    log "restarting useractivityd to refresh Continuity advertising state"
    /usr/bin/killall useractivityd 2>/dev/null
    sleep 3
    if "$PROBE" 10; then
        t1=$(date +%s)
        log "recovered in $((t1 - t0))s after intervention"
        notify "Clipboard hang detected — pboard restarted automatically."
        return 0
    fi
    log "recovery FAILED — will keep retrying next cycle"
    notify "Clipboard hang detected but auto-recovery failed. Try: killall -9 pboard"
    return 1
}

if [ ! -x "$PROBE" ]; then
    log "FATAL: probe binary not found at $PROBE — run install.sh first"
    exit 1
fi

log "watchdog started (interval=${INTERVAL}s timeout=${PROBE_TIMEOUT}s strikes=$STRIKES probe=$PROBE)"

consecutive=0
while true; do
    if "$PROBE" "$PROBE_TIMEOUT"; then
        if [ "$consecutive" -ge "$STRIKES" ]; then
            log "pasteboard responsive again without intervention"
        fi
        consecutive=0
    else
        rc=$?
        consecutive=$((consecutive + 1))
        log "probe failed rc=$rc (${consecutive}/${STRIKES})"
        if [ "$consecutive" -ge "$STRIKES" ]; then
            recover
            consecutive=0
        fi
    fi
    rotate_log
    sleep "$INTERVAL"
done
