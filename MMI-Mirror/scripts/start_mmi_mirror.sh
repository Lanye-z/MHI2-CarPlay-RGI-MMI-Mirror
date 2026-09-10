#!/bin/sh
# MMI Mirror production launcher.
# Final contract: Java owns terminal1/ctx80; Native renders displayable3 pixels only.
# Keep QNX /bin/sh compatibility: no set -e/set -u.

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || fail "Could not resolve script directory"
[ -n "$SCRIPT_DIR" ] || fail "Could not resolve script directory"
ROOT_DIR=$(dirname "$SCRIPT_DIR") || fail "Could not resolve runtime directory"

BIN="${MMI_MIRROR_BIN:-$ROOT_DIR/mmi-mirror-display}"
LOG="${MMI_MIRROR_LOG:-/tmp/mmi-mirror-display.log}"
LOG_MAX_BYTES="${MMI_MIRROR_LOG_MAX_BYTES:-524288}"
LOG_SINK="$SCRIPT_DIR/bounded_log.sh"
ACTIVE_MARKER="/tmp/mmi-mirror-active"
READY_MARKER="/tmp/mmi-mirror-basevideo.ready"

if [ ! -x "$BIN" ] && [ -x "$ROOT_DIR/build/mmi-mirror-display" ]; then
    BIN="$ROOT_DIR/build/mmi-mirror-display"
fi
[ -x "$BIN" ] || fail "executable not found: $BIN"
[ -f "$LOG_SINK" ] || fail "log sink not found: $LOG_SINK"

if [ -f "$ROOT_DIR/config.local" ]; then
    . "$ROOT_DIR/config.local" || fail "Could not load $ROOT_DIR/config.local"
fi

export IPL_CONFIG_DIR="${IPL_CONFIG_DIR:-/etc/eso/production}"
export LD_LIBRARY_PATH="/mnt/app/eso/lib:/eso/lib:/mnt/app/root/lib-target:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

MMI_CAPTURE_FPS="${MMI_CAPTURE_FPS:-30}"
MMI_CAPTURE_RECOVER_MS="${MMI_CAPTURE_RECOVER_MS:-3000}"
MMI_HMI_POLL_MS="${MMI_HMI_POLL_MS:-100}"

# Keep the three V1 aliases as compatibility fallbacks for an existing config.local.
LEGACY_SCALE="${MMI_CONTENT_SCALE:-0.80}"
LEGACY_X="${MMI_OFFSET_X:-0}"
LEGACY_Y="${MMI_OFFSET_Y:-0}"
MMI_CLASSIC_FULL_SCALE="${MMI_CLASSIC_FULL_SCALE:-$LEGACY_SCALE}"
MMI_CLASSIC_FULL_OFFSET_X="${MMI_CLASSIC_FULL_OFFSET_X:-$LEGACY_X}"
MMI_CLASSIC_FULL_OFFSET_Y="${MMI_CLASSIC_FULL_OFFSET_Y:-$LEGACY_Y}"
MMI_CLASSIC_SMALL_SCALE="${MMI_CLASSIC_SMALL_SCALE:-$LEGACY_SCALE}"
MMI_CLASSIC_SMALL_OFFSET_X="${MMI_CLASSIC_SMALL_OFFSET_X:-$LEGACY_X}"
MMI_CLASSIC_SMALL_OFFSET_Y="${MMI_CLASSIC_SMALL_OFFSET_Y:-$LEGACY_Y}"
MMI_SPORT_FULL_SCALE="${MMI_SPORT_FULL_SCALE:-$LEGACY_SCALE}"
MMI_SPORT_FULL_OFFSET_X="${MMI_SPORT_FULL_OFFSET_X:-$LEGACY_X}"
MMI_SPORT_FULL_OFFSET_Y="${MMI_SPORT_FULL_OFFSET_Y:-$LEGACY_Y}"
MMI_SPORT_SMALL_SCALE="${MMI_SPORT_SMALL_SCALE:-$LEGACY_SCALE}"
MMI_SPORT_SMALL_OFFSET_X="${MMI_SPORT_SMALL_OFFSET_X:-$LEGACY_X}"
MMI_SPORT_SMALL_OFFSET_Y="${MMI_SPORT_SMALL_OFFSET_Y:-$LEGACY_Y}"

# Old config.local files may still contain retired routing/seam variables.
# intentionally ignores them: the binary has no Native context-routing path
# and the Java/Native seam paths are fixed.
rm -f "$READY_MARKER" 2>/dev/null || true
echo "$$" > "$ACTIVE_MARKER" 2>/dev/null || true
trap 'rm -f "$ACTIVE_MARKER" "$READY_MARKER" 2>/dev/null || true' 0 1 2 15

{
    echo ""
    echo "===== $(date) MMI MIRROR  JAVA80 FINAL ====="
    echo "capture=1024x480 format=BGRA fps=$MMI_CAPTURE_FPS recover_ms=$MMI_CAPTURE_RECOVER_MS"
    echo "displayable=3 output=1440x455 native_context_routing=removed"
    echo "hmi_state=/tmp/mmi-mirror-hmi.state hmi_poll_ms=$MMI_HMI_POLL_MS basevideo_ready=$READY_MARKER"
    echo "context_owner=JAVA ctx80={98,101,102,3}"
    echo "profiles: CF=${MMI_CLASSIC_FULL_SCALE}@(${MMI_CLASSIC_FULL_OFFSET_X},${MMI_CLASSIC_FULL_OFFSET_Y}) CS=${MMI_CLASSIC_SMALL_SCALE}@(${MMI_CLASSIC_SMALL_OFFSET_X},${MMI_CLASSIC_SMALL_OFFSET_Y}) SF=${MMI_SPORT_FULL_SCALE}@(${MMI_SPORT_FULL_OFFSET_X},${MMI_SPORT_FULL_OFFSET_Y}) SS=${MMI_SPORT_SMALL_SCALE}@(${MMI_SPORT_SMALL_OFFSET_X},${MMI_SPORT_SMALL_OFFSET_Y})"
    echo "Starting foreground MMI mirror."
    echo "Log: $LOG (max ${LOG_MAX_BYTES} bytes + one .1 copy)"

    "$BIN" \
        --mmi \
        --capture-recover-ms "$MMI_CAPTURE_RECOVER_MS" \
        --fps "$MMI_CAPTURE_FPS" \
        --hmi-poll-ms "$MMI_HMI_POLL_MS" \
        --classic-full-scale "$MMI_CLASSIC_FULL_SCALE" \
        --classic-full-offset-x "$MMI_CLASSIC_FULL_OFFSET_X" \
        --classic-full-offset-y "$MMI_CLASSIC_FULL_OFFSET_Y" \
        --classic-small-scale "$MMI_CLASSIC_SMALL_SCALE" \
        --classic-small-offset-x "$MMI_CLASSIC_SMALL_OFFSET_X" \
        --classic-small-offset-y "$MMI_CLASSIC_SMALL_OFFSET_Y" \
        --sport-full-scale "$MMI_SPORT_FULL_SCALE" \
        --sport-full-offset-x "$MMI_SPORT_FULL_OFFSET_X" \
        --sport-full-offset-y "$MMI_SPORT_FULL_OFFSET_Y" \
        --sport-small-scale "$MMI_SPORT_SMALL_SCALE" \
        --sport-small-offset-x "$MMI_SPORT_SMALL_OFFSET_X" \
        --sport-small-offset-y "$MMI_SPORT_SMALL_OFFSET_Y" \
        --verbose \
        "$@"
} 2>&1 | /bin/sh "$LOG_SINK" "$LOG" "$LOG_MAX_BYTES"

STATUS=$?
rm -f "$ACTIVE_MARKER" "$READY_MARKER" 2>/dev/null || true
trap - 0 1 2 15
exit "$STATUS"
