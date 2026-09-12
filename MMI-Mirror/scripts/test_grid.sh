#!/bin/sh
# QNX diagnostic launcher: avoid set -u/set -e and validate critical inputs
# explicitly. Optional CLI arguments are passed through to the native binary.

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || fail "Could not resolve script directory"
[ -n "$SCRIPT_DIR" ] || fail "Could not resolve script directory"
ROOT_DIR=$(dirname "$SCRIPT_DIR") || fail "Could not resolve runtime directory"

BIN="${MMI_MIRROR_BIN:-$ROOT_DIR/mmi-mirror-display}"
LOG="${MMI_MIRROR_LOG:-/tmp/mmi-mirror-display.log}"

if [ ! -x "$BIN" ] && [ -x "$ROOT_DIR/build/mmi-mirror-display" ]; then
    BIN="$ROOT_DIR/build/mmi-mirror-display"
fi
[ -x "$BIN" ] || fail "executable not found: $BIN"
command -v tee >/dev/null 2>&1 || fail "tee command not found"

if [ -f "$ROOT_DIR/config.local" ]; then
    . "$ROOT_DIR/config.local" || fail "Could not load $ROOT_DIR/config.local"
fi

export IPL_CONFIG_DIR="${IPL_CONFIG_DIR:-/etc/eso/production}"
export LD_LIBRARY_PATH="/mnt/app/eso/lib:/eso/lib:/mnt/app/root/lib-target:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

VC_WIDTH="${VC_WIDTH:-1440}"
VC_HEIGHT="${VC_HEIGHT:-455}"
VC_DISPLAYABLE="${VC_DISPLAYABLE:-3}"
VC_CONTEXT="${VC_CONTEXT:-70}"
VC_DMDT_DISPLAY="${VC_DMDT_DISPLAY:-4}"
VC_RESTORE_CONTEXT="${VC_RESTORE_CONTEXT:-72}"

{
    echo ""
    echo "===== $(date) TEST GRID ====="
    echo "MMI Mirror display-backend diagnostic grid"
    echo "displayable=$VC_DISPLAYABLE context=$VC_CONTEXT display=$VC_DMDT_DISPLAY size=${VC_WIDTH}x${VC_HEIGHT} restore=$VC_RESTORE_CONTEXT"
} >> "$LOG" 2>/dev/null

echo "Starting foreground diagnostic grid."
echo "Press Ctrl+C to stop; context $VC_RESTORE_CONTEXT will be restored."
echo "Log: $LOG"

"$BIN" \
    --test \
    --width "$VC_WIDTH" \
    --height "$VC_HEIGHT" \
    --displayable "$VC_DISPLAYABLE" \
    --context "$VC_CONTEXT" \
    --display "$VC_DMDT_DISPLAY" \
    --restore-context "$VC_RESTORE_CONTEXT" \
    --verbose \
    "$@" 2>&1 | tee -a "$LOG"
