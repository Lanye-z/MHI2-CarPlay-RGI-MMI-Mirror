#!/bin/sh
# Start the installed MMI Mirror runtime without SSH.
# Manual start remains intentional; no OEM startup file is modified.

export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH

RUNTIME="/mnt/app/root/mmi-mirror"
BINARY="${RUNTIME}/mmi-mirror-display"
START_SCRIPT="${RUNTIME}/scripts/start_mmi_mirror.sh"
PIDFILE="/tmp/mmi-mirror-stage1.pid"
LOG="/tmp/mmi-mirror-display.log"

is_live_pid() {
    PID="$1"
    case "${PID}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "${PID}" 2>/dev/null
}

if [ -f "${PIDFILE}" ]; then
    OLD_PID=$(cat "${PIDFILE}" 2>/dev/null || echo "")
    if is_live_pid "${OLD_PID}"; then
        echo "MMI Mirror already appears to be running (wrapper PID ${OLD_PID})."
        echo "Use 'Stop MMI Mirror' before starting another session."
        exit 0
    fi
    rm -f "${PIDFILE}" 2>/dev/null || true
fi

if [ ! -d "${RUNTIME}" ]; then
    echo "ERROR: MMI Mirror runtime directory is missing: ${RUNTIME}"
    echo "Run 'Install/Update MMI Mirror' again."
    exit 1
fi
if [ ! -f "${BINARY}" ]; then
    echo "ERROR: Installed MMI Mirror binary is missing: ${BINARY}"
    exit 1
fi
if [ ! -x "${BINARY}" ]; then
    echo "ERROR: Installed MMI Mirror binary is not executable: ${BINARY}"
    exit 1
fi
if [ ! -f "${START_SCRIPT}" ]; then
    echo "ERROR: Missing runtime launcher: ${START_SCRIPT}"
    exit 1
fi

rm -f "${PIDFILE}" 2>/dev/null || true
if command -v nohup >/dev/null 2>&1; then
    nohup /bin/sh "${START_SCRIPT}" >/dev/null 2>&1 &
else
    /bin/sh "${START_SCRIPT}" >/dev/null 2>&1 &
fi
WRAPPER_PID=$!
echo "${WRAPPER_PID}" > "${PIDFILE}" 2>/dev/null || true

sleep 1
if is_live_pid "${WRAPPER_PID}"; then
    echo "MMI Mirror started. Wrapper PID: ${WRAPPER_PID}"
    echo "Runtime log: ${LOG}"
    echo "BaseVideo: displayable 3; Native context routing removed."
    echo "Cluster ownership: Java -> ctx80={98,101,102,3}."
    echo "Java diagnostics: /tmp/mmi-mirror-controller.log"
    exit 0
fi

rm -f "${PIDFILE}" 2>/dev/null || true
echo "ERROR: MMI Mirror exited during startup."
echo "Use 'Copy MMI Mirror diagnostics to SD-card' and inspect ${LOG}."
exit 1
