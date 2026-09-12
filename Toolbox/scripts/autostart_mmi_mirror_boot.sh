#!/bin/sh
# Boot-time launcher for the installed MMI Mirror V2.2 runtime.
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

echo "===== MMI Mirror V2.2 AutoStart boot runner ====="
date

# Sourced helper: boot delay + prerequisite wait. If it is missing (older
# installation), fall back to an equivalent inline implementation so AutoStart
# keeps working.
if [ -f "${SCRIPTDIR}/autostart_wait.sh" ]; then
    . "${SCRIPTDIR}/autostart_wait.sh"
else
    echo "WARN: ${SCRIPTDIR}/autostart_wait.sh missing; using the inline fallback"
    autostart_delay_seconds() {
        _raw=${1:-}
        case "${_raw}" in ''|*[!0-9]*) _raw=20 ;; esac
        [ "${_raw}" -gt 300 ] && _raw=300
        echo "${_raw}"
    }
    autostart_wait_for_prereqs() {
        AUTOSTART_WAIT_SECONDS=0
        _n=0
        while [ "${_n}" -lt "$2" ]; do
            [ -f "$3" ] || { AUTOSTART_WAIT_SECONDS=${_n}; return 1; }
            if [ "${_n}" -ge "$1" ] && [ -f "$4" ] && [ -f "$6" ] && \
               [ -x "$5" ] && [ -f "$7" ]; then
                AUTOSTART_WAIT_SECONDS=${_n}
                return 0
            fi
            sleep 1
            _n=$((_n + 1))
        done
        AUTOSTART_WAIT_SECONDS=${_n}
        return 2
    }
fi

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

# startup.sh can reach the hook before /mnt/app and the HMI Java controller are
# ready, and - more importantly - before the cluster (DCIVIDEO/Kombi) video path
# that this hook sits in front of: waitfor_quick isoTX2, devp-iso-mmx-mib2, then
# start_video_drivers (~+5 s) and start_late_drivers (~+15 s). The Native runtime
# creates its BaseVideo window exactly once, so starting it before that path is
# up leaves ctx80 with no visible layer -> black cluster (centre MMI unaffected).
# Therefore: wait for the installed runtime + Java controller AND for a boot
# delay counted from the moment this hook fired (MMI_AUTOSTART_DELAY, seconds,
# 0..300, default 20). Set it to 0 to restore the previous immediate start.
MMI_AUTOSTART_DELAY=$(autostart_delay_seconds "${MMI_AUTOSTART_DELAY:-20}")
echo "AutoStart boot delay: ${MMI_AUTOSTART_DELAY}s counted from the hook anchor"

autostart_wait_for_prereqs "${MMI_AUTOSTART_DELAY}" 120 "${MARKER}" "${START}" \
    "${BINARY}" "${LAUNCHER}" "${CONTROLLER_MARKER}"
WAIT_RC=$?
N=${AUTOSTART_WAIT_SECONDS}

if [ "${WAIT_RC}" -eq 1 ]; then
    write_status "DISABLED" "Persistent AutoStart marker is absent"
    echo "AutoStart marker is absent; exiting"
    exit 0
fi

if [ "${WAIT_RC}" -eq 2 ]; then
    write_status "FAILED" "Runtime/controller prerequisites were not ready within 120 seconds (boot delay ${MMI_AUTOSTART_DELAY}s)"
    echo "AutoStart timed out waiting for the installed runtime and Java controller (boot delay ${MMI_AUTOSTART_DELAY}s)"
    exit 1
fi

if runtime_active; then
    write_status "ACTIVE" "MMI Mirror was already running"
    echo "MMI Mirror is already active; nothing to do"
    exit 0
fi

write_status "STARTING" "Launching the normal Green Menu START path (boot delay ${MMI_AUTOSTART_DELAY}s)"
echo "AutoStart prerequisites ready after ${N} seconds (boot delay ${MMI_AUTOSTART_DELAY}s)"
/bin/sh "${START}"
START_RC=$?
if [ "${START_RC}" -ne 0 ]; then
    write_status "FAILED" "START helper exited with code ${START_RC}"
    echo "START helper failed with code ${START_RC}"
    exit "${START_RC}"
fi

# START verifies that the wrapper survived its first second. Require the real
# BaseVideo ready marker as the boot-time success gate.
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
