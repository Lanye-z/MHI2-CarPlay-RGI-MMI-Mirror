#!/bin/sh
# Bounded temporary log sink for MMI Mirror V2A diagnostics.
# QNX runtime helper: no set -u/set -e; inputs are validated explicitly.
# Mirrors input to stdout and to /tmp, keeping one rotated copy.

LOG="${1:-/tmp/mmi-mirror-display.log}"
MAX_BYTES="${2:-524288}"

if [ -z "$LOG" ]; then
    echo "ERROR: empty log path" >&2
    exit 1
fi
OLD="${LOG}.1"

case "$MAX_BYTES" in
    ''|*[!0-9]*) MAX_BYTES=524288 ;;
esac
if [ "$MAX_BYTES" -le 0 ]; then
    MAX_BYTES=524288
fi

log_size=0
if [ -f "$LOG" ]; then
    log_size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    case "$log_size" in
        ''|*[!0-9]*) log_size=0 ;;
    esac
fi

rotate_log() {
    rm -f "$OLD" 2>/dev/null || true
    if [ -f "$LOG" ]; then
        mv "$LOG" "$OLD" 2>/dev/null || rm -f "$LOG" 2>/dev/null || true
    fi
    log_size=0
}

if [ "$log_size" -ge "$MAX_BYTES" ]; then
    rotate_log
fi

while IFS= read -r line || [ -n "$line" ]; do
    # Preserve the foreground diagnostic stream even if /tmp logging fails.
    printf '%s\n' "$line"

    # Current V2A logs are ASCII. ${#line} is a sufficient byte estimate
    # and avoids spawning wc for every record.
    line_bytes=$((${#line} + 1))
    if [ "$log_size" -gt 0 ] && [ $((log_size + line_bytes)) -gt "$MAX_BYTES" ]; then
        rotate_log
    fi

    if printf '%s\n' "$line" >> "$LOG" 2>/dev/null; then
        log_size=$((log_size + line_bytes))
    fi
done

# QNX /bin/sh may otherwise propagate the final EOF/read status from the while loop.
# The sink has no fatal per-line writes by design, so successful input draining is exit 0.
exit 0
