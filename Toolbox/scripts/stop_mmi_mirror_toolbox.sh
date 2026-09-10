#!/bin/sh
# Gracefully stop MMI Mirror.
# has one Cluster context writer: Java ClusterStateController.
# Native has no Cluster context-routing path; withdrawing BaseVideo lifecycle
# lets Java release ctx80 back to stock ctx74 unless RGI still needs it.

export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH

RUNTIME="/mnt/app/root/mmi-mirror"
PIDFILE="/tmp/mmi-mirror-stage1.pid"
ACTIVE_MARKER="/tmp/mmi-mirror-active"
READY_MARKER="/tmp/mmi-mirror-basevideo.ready"

is_live_pid() {
    PID="$1"
    case "${PID}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "${PID}" 2>/dev/null
}

remaining_mmi_processes() {
    if ! command -v pidin >/dev/null 2>&1; then
        return 1
    fi
    pidin ar 2>/dev/null | grep '[m]mi-mirror-display' || true
}

echo "Stopping MMI Mirror (JAVA80)..."

# Keep the V1/V2A vehicle-proven termination path. Do not infer process state
# from slay's exit status: on QNX that status is not a reliable presence test.
if command -v slay >/dev/null 2>&1; then
    slay -f -v mmi-mirror-display 2>/dev/null || true
else
    echo "WARNING: slay command not found; using wrapper termination only."
fi

sleep 1

if [ -f "${PIDFILE}" ]; then
    WRAPPER_PID=$(cat "${PIDFILE}" 2>/dev/null || echo "")
    if is_live_pid "${WRAPPER_PID}"; then
        kill -TERM "${WRAPPER_PID}" 2>/dev/null || true
        sleep 1
    fi
    rm -f "${PIDFILE}" 2>/dev/null || true
fi

rm -f "${ACTIVE_MARKER}" "${READY_MARKER}" 2>/dev/null || true
sync 2>/dev/null || true

# If pidin is available, verify by actual process-list output rather than the
# return code of `slay -p`. If pidin is unavailable, preserve the proven V2A
# behavior and trust the slay + wrapper termination sequence above.
if command -v pidin >/dev/null 2>&1; then
    REMAINING="$(remaining_mmi_processes)"
    if [ -n "${REMAINING}" ]; then
        echo "ERROR: mmi-mirror-display is still running after stop request:" >&2
        echo "${REMAINING}" >&2
        exit 1
    fi
fi

echo "MMI Mirror stop request completed; Java controller owns stock/composite release."
exit 0
