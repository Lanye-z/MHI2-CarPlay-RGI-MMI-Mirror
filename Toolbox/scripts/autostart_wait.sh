#!/bin/sh
# Sourced helper for the MMI Mirror V2.2 boot AutoStart runner.
#
# Why this exists (and why the delay is not just a sleep):
# the AutoStart hook lives at the "# DCIVIDEO: Kombi Map" anchor in
# /etc/boot/startup.sh, and the *cluster* video path is brought up AFTER that
# anchor in the same function:
#
#   <hook>  waitfor_quick .../isoTX2         (Kombi DCIVIDEO transmit device)
#           devp-iso-mmx-mib2 ... -MisoTX2
#           ham; sleep 5; start_video_drivers     (~+5 s)
#           sleep 10;  start_late_drivers         (~+15 s)
#
# The Native runtime creates its BaseVideo window (displayable 3) once, at
# start-up, and never recreates it. If that window is created before the cluster
# output path exists, the display manager does not composite it, and because
# ctx80 replaces the stock Kombi map displayable 33 with {98,101,102,3} the
# cluster ends up with no visible layer at all -> black cluster (the centre MMI
# display is unaffected). Measured on the car: the window was created ~2.6 s
# before start_video_drivers and ~12.6 s before start_late_drivers.
#
# So the boot runner must not start the runtime too early. The delay is counted
# from the moment the hook fired (i.e. from the first iteration of the wait
# below), which is the same reference point the startup.sh video steps use -
# not from "whenever the Java controller happened to appear".
#
# No side effects when sourced: definitions only.

# autostart_delay_seconds [raw] -> echoes a valid delay (0..300, default 20).
autostart_delay_seconds() {
    _raw=${1:-}
    case "${_raw}" in
        ''|*[!0-9]*) _raw=20 ;;
    esac
    [ "${_raw}" -gt 300 ] && _raw=300
    echo "${_raw}"
}

# autostart_wait_for_prereqs DELAY TIMEOUT MARKER START BINARY LAUNCHER CONTROLLER_MARKER
#
#   waits until all of:
#     * at least DELAY seconds have passed since the hook fired,
#     * the installed runtime is present (START script, binary, launcher),
#     * the Java controller marker exists (it writes /tmp/mmi-mirror-controller.started),
#   or until TIMEOUT seconds have passed.
#
#   returns 0  prerequisites ready
#           1  the persistent AutoStart marker disappeared (disabled while booting)
#           2  timeout
#   and sets AUTOSTART_WAIT_SECONDS to the number of seconds waited.
autostart_wait_for_prereqs() {
    _delay=$1
    _timeout=$2
    _marker=$3
    _start=$4
    _bin=$5
    _launcher=$6
    _controller=$7

    AUTOSTART_WAIT_SECONDS=0
    _n=0
    while [ "${_n}" -lt "${_timeout}" ]; do
        if [ ! -f "${_marker}" ]; then
            AUTOSTART_WAIT_SECONDS=${_n}
            return 1
        fi
        if [ "${_n}" -ge "${_delay}" ] && [ -f "${_start}" ] && \
           [ -f "${_launcher}" ] && [ -x "${_bin}" ] && [ -f "${_controller}" ]; then
            AUTOSTART_WAIT_SECONDS=${_n}
            return 0
        fi
        sleep 1
        _n=$((_n + 1))
    done
    AUTOSTART_WAIT_SECONDS=${_n}
    return 2
}
