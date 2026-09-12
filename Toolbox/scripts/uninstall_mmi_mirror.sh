#!/bin/sh
# MMI Mirror V2.2 / JAVA80 final composite uninstaller for MIB2 Toolbox.
# Restores the stable RGI recovery JAR + displayable20 renderer whenever any RGI
# native payload remains. Stable RGI source files on the SD card are never changed.
# No Native context write is used; Java owns/relinquishes terminal1 until reboot.

export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/media/gracenote/bin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH

if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )

. "${SCRIPTDIR}/util_info.sh"
. "${SCRIPTDIR}/util_mountsd.sh"
if [ -z "${VOLUME:-}" ]; then
    echo "No SD-card found, quitting"
    exit 1
fi

APP_TARGET="/mnt/app/root/mmi-mirror"
STAGE_DIR="${APP_TARGET}.new"
ROLLBACK_DIR="${APP_TARGET}.rollback"

JAR_TARGET_DIR="/mnt/app/eso/hmi/lsd/jars"
JAR_TARGET="${JAR_TARGET_DIR}/carplay_hook.jar"
STABLE_RGI_JAR="${VOLUME}/Toolbox/apps/carplay-rgi/carplay_hook.jar"
STABLE_RGI_RENDERER="${VOLUME}/Toolbox/apps/carplay-rgi/maneuver_render"

RGI_HOOK_DIR="/mnt/app/root/hooks"
RGI_NATIVE_1="${RGI_HOOK_DIR}/libcarplay_hook.so"
RGI_NATIVE_2="${RGI_HOOK_DIR}/maneuver_render"
RGI_NATIVE_3="${RGI_HOOK_DIR}/flag_atlas.rgba"

BACKUPFOLDER="${VOLUME}/Backup/${VERSION}/MMIMirror"
LOGFILE="${BACKUPFOLDER}/uninstall_mmi_mirror.log"
JAR_TXN_DIR="${BACKUPFOLDER}/.carplay_hook_jar_transaction"
RGI_RENDERER_TXN_DIR="${BACKUPFOLDER}/.rgi_renderer_transaction"
ACTIVE_MARKER="/tmp/mmi-mirror-active"
READY_MARKER="/tmp/mmi-mirror-basevideo.ready"
AUTOSTART_MARKER="${SCRIPTDIR}/.mmi_mirror_autostart"
AUTOSTART_SCRIPT="${SCRIPTDIR}/autostart_mmi_mirror_off.sh"
AUTOSTART_BEGIN="# MMI MIRROR V2.2 AUTOSTART BEGIN"
STARTUP="/etc/boot/startup.sh"

exec 3>&1
mkdir -p "${BACKUPFOLDER}" || exit 1
touch "${BACKUPFOLDER}/DONT_TOUCH_ANYTHING_HERE" 2>/dev/null || true
touch "${LOGFILE}" || exit 1
exec >> "${LOGFILE}" 2>&1

log() {
    echo "$*"
    echo "$*" >&3
}

file_size() {
    RAW_SIZE=$(wc -c < "$1" 2>/dev/null) || {
        echo 0
        return
    }
    set -- ${RAW_SIZE}
    case "${1:-}" in
        ''|*[!0-9]*) echo 0 ;;
        *) echo "$1" ;;
    esac
}

artifact_sane() {
    FILE="$1"
    [ -s "${FILE}" ] || return 1
    SIZE=$(file_size "${FILE}")
    case "${SIZE}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "${SIZE}" -ge 10000 ]
}

remount_read_only() {
    mount -ur /mnt/app 2>/dev/null
}

fail() {
    trap - 1 2 15
    log "ERROR: $*"
    remount_read_only 2>/dev/null || log "WARNING: /mnt/app could not be remounted read-only"
    log "Uninstall log: Backup/${VERSION}/MMIMirror/uninstall_mmi_mirror.log"
    exit 1
}

copy_checked_no_fail() {
    SRC="$1"
    DST="$2"
    MODE="$3"

    cp "${SRC}" "${DST}" || return 1
    chmod "${MODE}" "${DST}" || return 1

    SRC_SIZE=$(file_size "${SRC}")
    DST_SIZE=$(file_size "${DST}")
    if [ "${SRC_SIZE}" != "${DST_SIZE}" ] || [ "${SRC_SIZE}" = "0" ]; then
        return 1
    fi

    if command -v cksum >/dev/null 2>&1; then
        SRC_SUM=$(cksum < "${SRC}" 2>/dev/null || echo source-error)
        DST_SUM=$(cksum < "${DST}" 2>/dev/null || echo target-error)
        if [ "${SRC_SUM}" != "${DST_SUM}" ]; then
            return 1
        fi
    fi
    return 0
}

count_rgi_native_payloads() {
    COUNT=0
    [ -f "${RGI_NATIVE_1}" ] && COUNT=$((COUNT + 1))
    [ -f "${RGI_NATIVE_2}" ] && COUNT=$((COUNT + 1))
    [ -f "${RGI_NATIVE_3}" ] && COUNT=$((COUNT + 1))
    echo "${COUNT}"
}

disable_autostart() {
    HAS_BLOCK=0
    [ -f "${STARTUP}" ] && grep -qF "${AUTOSTART_BEGIN}" "${STARTUP}" 2>/dev/null && HAS_BLOCK=1
    if [ ! -f "${AUTOSTART_MARKER}" ] && [ "${HAS_BLOCK}" -eq 0 ]; then
        return 0
    fi

    if [ -f "${AUTOSTART_SCRIPT}" ]; then
        /bin/sh "${AUTOSTART_SCRIPT}"
        return $?
    fi

    # Fallback for an incomplete Toolbox update where the OFF helper is absent.
    mount -uw /mnt/app 2>/dev/null || return 1
    rm -f "${AUTOSTART_MARKER}" || {
        mount -ur /mnt/app 2>/dev/null
        return 1
    }
    sync
    mount -ur /mnt/app 2>/dev/null || return 1

    if [ "${HAS_BLOCK}" -eq 1 ]; then
        mount -uw /mnt/system 2>/dev/null || return 1
        sed -i '/# MMI MIRROR V2.2 AUTOSTART BEGIN/,/# MMI MIRROR V2.2 AUTOSTART END/d' "${STARTUP}" || {
            mount -ur /mnt/system 2>/dev/null
            return 1
        }
        sync
        mount -ur /mnt/system 2>/dev/null || return 1
    fi
    return 0
}

trap 'fail "Uninstall interrupted by signal"' 1 2 15

log "===== MMI Mirror V2.2 / JAVA80 uninstall started ====="
log "Firmware: ${VERSION}"
log "FAZIT: ${FAZIT}"
log "Runtime target: ${APP_TARGET}"
log "JAR target: ${JAR_TARGET}"
log "Stable RGI recovery source: ${VOLUME}/Toolbox/apps/carplay-rgi"

log "Disabling the persistent MMI Mirror AutoStart hook, if present"
disable_autostart || fail "Could not completely remove the MMI Mirror AutoStart state"

# Stop BaseVideo while the installed runtime scripts still exist. If RGI currently
# presents a frame, Java may intentionally keep ctx80 owned until RGI ends/reboot.
if [ -f "${SCRIPTDIR}/stop_mmi_mirror_toolbox.sh" ]; then
    log "Stopping MMI BaseVideo and withdrawing lifecycle markers"
    /bin/sh "${SCRIPTDIR}/stop_mmi_mirror_toolbox.sh" || fail "Could not stop MMI Mirror"
else
    log "WARNING: stop helper missing; using marker/process fallback without Native context routing"
    if command -v slay >/dev/null 2>&1; then
        slay -f -v mmi-mirror-display 2>/dev/null || true
    fi
    rm -f "${ACTIVE_MARKER}" "${READY_MARKER}" /tmp/mmi-mirror-stage1.pid 2>/dev/null || true
    sync 2>/dev/null || true
fi

if [ -f "${APP_TARGET}/INSTALL_INFO.txt" ]; then
    cp "${APP_TARGET}/INSTALL_INFO.txt" "${BACKUPFOLDER}/last_INSTALL_INFO.txt" 2>/dev/null || true
fi
if [ -f "${APP_TARGET}/config.local" ]; then
    cp "${APP_TARGET}/config.local" "${BACKUPFOLDER}/last_config.local" 2>/dev/null || true
fi

RGI_NATIVE_COUNT=$(count_rgi_native_payloads)
if [ "${RGI_NATIVE_COUNT}" -gt 0 ]; then
    if ! artifact_sane "${STABLE_RGI_JAR}"; then
        fail "RGI native payload(s) detected (${RGI_NATIVE_COUNT}/3), but stable RGI JAR is missing/invalid: ${STABLE_RGI_JAR}"
    fi
    if ! artifact_sane "${STABLE_RGI_RENDERER}"; then
        fail "RGI native payload(s) detected (${RGI_NATIVE_COUNT}/3), but stable RGI renderer is missing/invalid: ${STABLE_RGI_RENDERER}"
    fi
fi

log "Mounting /mnt/app read-write"
mount -uw /mnt/app || fail "Could not mount /mnt/app read-write"

if [ -d "${APP_TARGET}" ]; then
    log "Removing ${APP_TARGET}"
    rm -rf "${APP_TARGET}" || fail "Could not remove ${APP_TARGET}"
else
    log "Runtime directory already absent: ${APP_TARGET}"
fi
rm -rf "${STAGE_DIR}" "${ROLLBACK_DIR}" 2>/dev/null || fail "Could not remove stale MMI Mirror runtime transaction directories"
if [ -e "${APP_TARGET}" ] || [ -e "${STAGE_DIR}" ] || [ -e "${ROLLBACK_DIR}" ]; then
    fail "Uninstall verification failed: an MMI Mirror runtime directory still exists"
fi

rm -f "${JAR_TARGET}.mmi-mirror.tmp" "${JAR_TARGET}.mmi-mirror.rollback.tmp" \
      "${RGI_NATIVE_2}.mmi-mirror.tmp" "${RGI_NATIVE_2}.mmi-mirror.rollback.tmp" 2>/dev/null || true

if [ "${RGI_NATIVE_COUNT}" -eq 0 ]; then
    log "RGI native payload state: absent (0/3); removing carplay_hook.jar owned by MMI Mirror"
    rm -f "${JAR_TARGET}" || fail "Could not remove ${JAR_TARGET}"
else
    if [ "${RGI_NATIVE_COUNT}" -eq 3 ]; then
        log "RGI native payload state: complete (3/3); restoring stable RGI JAR + displayable20 renderer"
    else
        log "WARNING: RGI native payload state is partial (${RGI_NATIVE_COUNT}/3); restoring stable RGI JAR + renderer as safest recoverable state"
    fi

    mkdir -p "${JAR_TARGET_DIR}" "${RGI_HOOK_DIR}" || fail "Could not create RGI/JAR target directories"

    if ! copy_checked_no_fail "${STABLE_RGI_RENDERER}" "${RGI_NATIVE_2}.mmi-mirror.tmp" 755; then
        rm -f "${RGI_NATIVE_2}.mmi-mirror.tmp" 2>/dev/null || true
        fail "Could not stage stable RGI maneuver_render"
    fi
    mv "${RGI_NATIVE_2}.mmi-mirror.tmp" "${RGI_NATIVE_2}" || fail "Could not restore stable RGI maneuver_render"
    log "Stable RGI displayable20 maneuver_render restored from ${STABLE_RGI_RENDERER}"

    if ! copy_checked_no_fail "${STABLE_RGI_JAR}" "${JAR_TARGET}.mmi-mirror.tmp" 644; then
        rm -f "${JAR_TARGET}.mmi-mirror.tmp" 2>/dev/null || true
        fail "Could not stage stable RGI carplay_hook.jar"
    fi
    mv "${JAR_TARGET}.mmi-mirror.tmp" "${JAR_TARGET}" || fail "Could not restore stable RGI carplay_hook.jar"
    log "Stable RGI carplay_hook.jar restored from ${STABLE_RGI_JAR}"
fi

rm -rf "${JAR_TXN_DIR}" "${RGI_RENDERER_TXN_DIR}" 2>/dev/null || fail "Could not remove stale MMI Mirror payload transactions"
rm -f /tmp/mmi-mirror-stage1.pid "${ACTIVE_MARKER}" "${READY_MARKER}" 2>/dev/null || true

log "Synchronizing filesystem changes"
sync || fail "sync failed"

if remount_read_only; then
    log "/mnt/app remounted read-only"
else
    log "WARNING: uninstall completed but /mnt/app could not be remounted read-only"
fi
trap - 1 2 15

log "MMI Mirror V2.2 / JAVA80 final composite uninstalled successfully."
if [ "${RGI_NATIVE_COUNT}" -eq 0 ]; then
    log "Final policy: no RGI native payloads detected; MMI-owned carplay_hook.jar removed."
else
    log "Final policy: stable RGI carplay_hook.jar + displayable20 maneuver_render restored."
fi
log "RGI libcarplay_hook.so, flag_atlas.rgba, GEM/scripts and JSON configuration were not removed."
log "IMPORTANT: reboot/HMI restart is REQUIRED before using RGI again; the currently loaded Unified JAR/renderer process may persist until restart."
log "Persistent AutoStart marker and startup.sh hook were removed."
log "Runtime logs in /tmp were intentionally retained for collection until reboot/clear."
log "Uninstall log: Backup/${VERSION}/MMIMirror/uninstall_mmi_mirror.log"
log "===== MMI Mirror V2.2 / JAVA80 uninstall finished ====="
exit 0
