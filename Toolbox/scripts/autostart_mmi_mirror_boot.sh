#!/bin/sh
# Boot-time launcher for the installed MMI Mirror runtime.
# The startup.sh hook runs this in the background; failure leaves stock routing intact.

export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH

SCRIPTDIR="/mnt/app/eso/hmi/engdefs/scripts/mqb"
MARKER="${SCRIPTDIR}/.mmi_mirror_autostart"
START="${SCRIPTDIR}/start_mmi_mirror_toolbox.sh"
STOP="${SCRIPTDIR}/stop_mmi_mirror_toolbox.sh"
RUNTIME="/mnt/app/root/mmi-mirror"
BINARY="${RUNTIME}/mmi-mirror-display"
LAUNCHER="${RUNTIME}/scripts/start_mmi_mirror.sh"
PIDFILE="/tmp/mmi-mirror-stage1.pid"
ACTIVE_MARKER="/tmp/mmi-mirror-active"
READY_MARKER="/tmp/mmi-mirror-basevideo.ready"
CONTROLLER_MARKER="/tmp/mmi-mirror-controller.started"
LOG="/tmp/mmi-mirror-autostart.log"
STATUS="/tmp/mmi-mirror-autostart.status"

: > "${LOG}"
exec >> "${LOG}" 2>&1

echo "===== MMI Mirror AutoStart boot runner ====="
date

is_live_pid() {
    PID="$1"
    case "${PID}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "${PID}" 2>/dev/null
}

runtime_active() {
    [ -f "${PIDFILE}" ] || return 1
    PID=$(cat "${PIDFILE}" 2>/dev/null || echo "")
    is_live_pid "${PID}" || return 1
    [ -f "${ACTIVE_MARKER}" ] || return 1
    return 0
}

write_status() {
    {
        echo "version=mmi-mirror-autostart-v1"
        echo "state=$1"
        echo "detail=$2"
        echo "runtime=${RUNTIME}"
        date
    } > "${STATUS}"
}

N=0
while [ "${N}" -lt 120 ]; do
    [ -f "${MARKER}" ] || {
        write_status "DISABLED" "Persistent AutoStart marker is absent"
        echo "AutoStart marker is absent; exiting"
        exit 0
    }

    if [ -f "${START}" ] && [ -x "${BINARY}" ] && [ -f "${LAUNCHER}" ] && \
       [ -f "${CONTROLLER_MARKER}" ]; then
        break
    fi

    sleep 1
    N=$((N + 1))
done

if [ "${N}" -ge 120 ]; then
    write_status "FAILED" "Runtime/controller prerequisites were not ready within 120 seconds"
    echo "AutoStart timed out waiting for the installed runtime and Java controller"
    exit 1
fi

if runtime_active; then
    write_status "ACTIVE" "MMI Mirror was already running"
    echo "MMI Mirror is already active; nothing to do"
    exit 0
fi

write_status "STARTING" "Launching the normal Green Menu START path"
echo "AutoStart prerequisites ready after ${N} seconds"
/bin/sh "${START}"
START_RC=$?
if [ "${START_RC}" -ne 0 ]; then
    write_status "FAILED" "START helper exited with code ${START_RC}"
    echo "START helper failed with code ${START_RC}"
    exit "${START_RC}"
fi

N=0
while [ "${N}" -lt 60 ]; do
    [ -f "${MARKER}" ] || {
        [ -f "${STOP}" ] && /bin/sh "${STOP}" >/dev/null 2>&1
        write_status "DISABLED" "AutoStart marker was removed while starting"
        exit 0
    }

    if runtime_active && [ -f "${READY_MARKER}" ]; then
        write_status "ACTIVE" "BaseVideo reached ready state"
        echo "AutoStart succeeded: MMI Mirror BaseVideo is ready"
        date
        exit 0
    fi

    sleep 1
    N=$((N + 1))
done

[ -f "${STOP}" ] && /bin/sh "${STOP}" >/dev/null 2>&1
write_status "FAILED" "BaseVideo did not reach ready state within 60 seconds"
echo "AutoStart failed readiness verification; stopped the incomplete session"
date
exit 1
