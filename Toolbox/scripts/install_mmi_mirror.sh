#!/bin/sh
# MMI Mirror V2.2 / JAVA80 final composite installer for MIB2 Toolbox.
#
# Ownership contract:
# - Java ClusterStateController is the only Cluster context writer.
# - Native MMI renders displayable3 only.
# - When stable RGI is complete (3/3), this installer transactionally swaps only
#   its maneuver_render to the V2.2 displayable98/no-dmdt renderer.
# - Stable RGI recovery payloads under Toolbox/apps/carplay-rgi are never modified.
# - Unified JAR has no hard-coded expected-size gate; copy integrity still uses
#   source/destination size equality and cksum when available.

export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/media/gracenote/bin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH

if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )

. "${SCRIPTDIR}/util_info.sh"
. "${SCRIPTDIR}/util_mountsd.sh"
if [ -z "${VOLUME:-}" ]; then
    echo "No SD-card found, quitting"
    exit 1
fi

APP_SOURCE="${VOLUME}/Toolbox/apps/mmi-mirror"
APP_TARGET="/mnt/app/root/mmi-mirror"
STAGE_DIR="${APP_TARGET}.new"
ROLLBACK_DIR="${APP_TARGET}.rollback"

JAR_SOURCE="${APP_SOURCE}/carplay_hook-unified.jar"
JAR_TARGET_DIR="/mnt/app/eso/hmi/lsd/jars"
JAR_TARGET="${JAR_TARGET_DIR}/carplay_hook.jar"

RGI_HOOK_DIR="/mnt/app/root/hooks"
RGI_NATIVE_1="${RGI_HOOK_DIR}/libcarplay_hook.so"
RGI_NATIVE_2="${RGI_HOOK_DIR}/maneuver_render"
RGI_NATIVE_3="${RGI_HOOK_DIR}/flag_atlas.rgba"
RGI98_SOURCE="${APP_SOURCE}/maneuver_render-rgi98"
STABLE_RGI_JAR="${VOLUME}/Toolbox/apps/carplay-rgi/carplay_hook.jar"
STABLE_RGI_RENDERER="${VOLUME}/Toolbox/apps/carplay-rgi/maneuver_render"

BACKUPFOLDER="${VOLUME}/Backup/${VERSION}/MMIMirror"
LOGFILE="${BACKUPFOLDER}/install_mmi_mirror.log"
JAR_TXN_DIR="${BACKUPFOLDER}/.carplay_hook_jar_transaction"
RGI_RENDERER_TXN_DIR="${BACKUPFOLDER}/.rgi_renderer_transaction"
SELFTEST_LOG="/tmp/mmi-mirror-install-selftest.log"
LAUNCHER_SELFTEST_BIN="/tmp/mmi-mirror-launcher-selftest-bin.sh"
LAUNCHER_SELFTEST_LOG="/tmp/mmi-mirror-launcher-selftest.log"
LAUNCHER_SELFTEST_STDOUT="/tmp/mmi-mirror-launcher-selftest.stdout"

SWAP_STARTED=0
HAD_TARGET=0
JAR_TXN_ACTIVE=0
RGI_RENDERER_TXN_ACTIVE=0
RGI98_DEPLOYED=0

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

cleanup_launcher_selftest() {
    rm -f "${LAUNCHER_SELFTEST_BIN}" "${LAUNCHER_SELFTEST_LOG}" \
          "${LAUNCHER_SELFTEST_LOG}.1" "${LAUNCHER_SELFTEST_STDOUT}" \
          2>/dev/null || true
}

runtime_valid() {
    DIR="$1"
    [ -d "${DIR}" ] && \
    [ -s "${DIR}/mmi-mirror-display" ] && \
    [ -f "${DIR}/scripts/start_mmi_mirror.sh" ] && \
    [ -f "${DIR}/scripts/bounded_log.sh" ] && \
    [ -f "${DIR}/scripts/restore_map.sh" ]
}

count_rgi_native_payloads() {
    COUNT=0
    [ -f "${RGI_NATIVE_1}" ] && COUNT=$((COUNT + 1))
    [ -f "${RGI_NATIVE_2}" ] && COUNT=$((COUNT + 1))
    [ -f "${RGI_NATIVE_3}" ] && COUNT=$((COUNT + 1))
    echo "${COUNT}"
}

mmi_process_running() {
    if ! command -v pidin >/dev/null 2>&1; then
        return 1
    fi
    pidin ar 2>/dev/null | grep '[m]mi-mirror-display' >/dev/null 2>&1
}

restore_carplay_jar_snapshot() {
    if [ ! -d "${JAR_TXN_DIR}" ]; then
        JAR_TXN_ACTIVE=0
        return 0
    fi

    rm -f "${JAR_TARGET}.mmi-mirror.tmp" "${JAR_TARGET}.mmi-mirror.rollback.tmp" 2>/dev/null || true

    if [ -f "${JAR_TXN_DIR}/present" ]; then
        mkdir -p "${JAR_TARGET_DIR}" || return 1
        if cp "${JAR_TXN_DIR}/carplay_hook.jar" "${JAR_TARGET}.mmi-mirror.rollback.tmp" && \
           chmod 644 "${JAR_TARGET}.mmi-mirror.rollback.tmp" && \
           mv "${JAR_TARGET}.mmi-mirror.rollback.tmp" "${JAR_TARGET}"
        then
            log "Rollback restored pre-install ${JAR_TARGET}"
        else
            log "ROLLBACK ERROR: Could not restore pre-install ${JAR_TARGET}"
            return 1
        fi
    elif [ -f "${JAR_TXN_DIR}/absent" ]; then
        if rm -f "${JAR_TARGET}" "${JAR_TARGET}.mmi-mirror.tmp" "${JAR_TARGET}.mmi-mirror.rollback.tmp"; then
            log "Rollback removed newly installed ${JAR_TARGET}"
        else
            log "ROLLBACK ERROR: Could not remove newly installed ${JAR_TARGET}"
            return 1
        fi
    else
        log "ROLLBACK ERROR: JAR transaction has no present/absent marker"
        return 1
    fi

    rm -rf "${JAR_TXN_DIR}" 2>/dev/null || return 1
    JAR_TXN_ACTIVE=0
    return 0
}

restore_rgi_renderer_snapshot() {
    if [ ! -d "${RGI_RENDERER_TXN_DIR}" ]; then
        RGI_RENDERER_TXN_ACTIVE=0
        return 0
    fi

    rm -f "${RGI_NATIVE_2}.mmi-mirror.tmp" "${RGI_NATIVE_2}.mmi-mirror.rollback.tmp" 2>/dev/null || true

    if [ -f "${RGI_RENDERER_TXN_DIR}/present" ]; then
        mkdir -p "${RGI_HOOK_DIR}" || return 1
        if cp "${RGI_RENDERER_TXN_DIR}/maneuver_render" "${RGI_NATIVE_2}.mmi-mirror.rollback.tmp" && \
           chmod 755 "${RGI_NATIVE_2}.mmi-mirror.rollback.tmp" && \
           mv "${RGI_NATIVE_2}.mmi-mirror.rollback.tmp" "${RGI_NATIVE_2}"
        then
            log "Rollback restored pre-install RGI renderer ${RGI_NATIVE_2}"
        else
            log "ROLLBACK ERROR: Could not restore pre-install RGI renderer"
            return 1
        fi
    elif [ -f "${RGI_RENDERER_TXN_DIR}/absent" ]; then
        if rm -f "${RGI_NATIVE_2}" "${RGI_NATIVE_2}.mmi-mirror.tmp" "${RGI_NATIVE_2}.mmi-mirror.rollback.tmp"; then
            log "Rollback removed newly installed RGI renderer"
        else
            log "ROLLBACK ERROR: Could not remove newly installed RGI renderer"
            return 1
        fi
    else
        log "ROLLBACK ERROR: RGI renderer transaction has no present/absent marker"
        return 1
    fi

    rm -rf "${RGI_RENDERER_TXN_DIR}" 2>/dev/null || return 1
    RGI_RENDERER_TXN_ACTIVE=0
    return 0
}

rollback_installation() {
    trap - 1 2 15
    RESULT=0
    log "Rollback started"

    mount -uw /mnt/app 2>/dev/null || RESULT=1

    if [ "${SWAP_STARTED}" -eq 1 ]; then
        rm -rf "${STAGE_DIR}" 2>/dev/null || RESULT=1

        if [ "${HAD_TARGET}" -eq 1 ]; then
            if [ -d "${ROLLBACK_DIR}" ]; then
                rm -rf "${APP_TARGET}" 2>/dev/null || RESULT=1
                mv "${ROLLBACK_DIR}" "${APP_TARGET}" 2>/dev/null || RESULT=1
            else
                log "Rollback note: no runtime rollback directory exists; leaving current target untouched"
            fi
        else
            rm -rf "${APP_TARGET}" 2>/dev/null || RESULT=1
            rm -rf "${ROLLBACK_DIR}" 2>/dev/null || true
        fi
    fi

    if [ "${JAR_TXN_ACTIVE}" -eq 1 ] || [ -f "${JAR_TXN_DIR}/active" ]; then
        restore_carplay_jar_snapshot || RESULT=1
    fi
    if [ "${RGI_RENDERER_TXN_ACTIVE}" -eq 1 ] || [ -f "${RGI_RENDERER_TXN_DIR}/active" ]; then
        restore_rgi_renderer_snapshot || RESULT=1
    fi

    sync 2>/dev/null || RESULT=1
    remount_read_only || RESULT=1

    if [ "${RESULT}" -eq 0 ]; then
        log "Rollback completed; previous runtime, carplay_hook.jar and RGI renderer state restored"
    else
        log "ROLLBACK INCOMPLETE: inspect ${APP_TARGET}, ${ROLLBACK_DIR}, ${JAR_TARGET}, ${RGI_NATIVE_2}, ${JAR_TXN_DIR}, and ${RGI_RENDERER_TXN_DIR}"
    fi
    return "${RESULT}"
}

fail() {
    MESSAGE="$*"
    cleanup_launcher_selftest
    log "ERROR: ${MESSAGE}"

    if [ "${SWAP_STARTED}" -eq 1 ] || [ "${JAR_TXN_ACTIVE}" -eq 1 ] || [ "${RGI_RENDERER_TXN_ACTIVE}" -eq 1 ] || \
       [ -f "${JAR_TXN_DIR}/active" ] || [ -f "${RGI_RENDERER_TXN_DIR}/active" ]; then
        rollback_installation || true
    else
        rm -rf "${STAGE_DIR}" 2>/dev/null || true
        remount_read_only 2>/dev/null || true
    fi

    log "Installation aborted. Log: Backup/${VERSION}/MMIMirror/install_mmi_mirror.log"
    exit 1
}

copy_checked() {
    SRC="$1"
    DST="$2"
    MODE="$3"

    cp "${SRC}" "${DST}" || fail "Could not copy ${SRC}"
    chmod "${MODE}" "${DST}" || fail "Could not chmod ${DST}"

    SRC_SIZE=$(file_size "${SRC}")
    DST_SIZE=$(file_size "${DST}")
    if [ "${SRC_SIZE}" != "${DST_SIZE}" ] || [ "${SRC_SIZE}" = "0" ]; then
        fail "Copy verification failed for ${SRC}"
    fi

    if command -v cksum >/dev/null 2>&1; then
        SRC_SUM=$(cksum < "${SRC}" 2>/dev/null || echo source-error)
        DST_SUM=$(cksum < "${DST}" 2>/dev/null || echo target-error)
        if [ "${SRC_SUM}" != "${DST_SUM}" ]; then
            fail "Checksum verification failed for ${SRC}"
        fi
    fi
}

find_payload() {
    BINARY_SOURCE=""
    for CANDIDATE in \
        "${APP_SOURCE}/mmi-mirror-display" \
        "${VOLUME}/MMI-Mirror/mmi-mirror-display" \
        "${VOLUME}/MMI-Mirror/build/mmi-mirror-display"
    do
        if [ -s "${CANDIDATE}" ]; then
            BINARY_SOURCE="${CANDIDATE}"
            break
        fi
    done

    if [ -z "${BINARY_SOURCE}" ]; then
        fail "QNX ARMv7 payload mmi-mirror-display not found. Place it in Toolbox/apps/mmi-mirror/."
    fi

    if [ -f "${APP_SOURCE}/scripts/start_mmi_mirror.sh" ] && \
       [ -f "${APP_SOURCE}/scripts/bounded_log.sh" ] && \
       [ -f "${APP_SOURCE}/scripts/restore_map.sh" ]; then
        RUNTIME_SCRIPTS="${APP_SOURCE}/scripts"
    elif [ -f "${VOLUME}/MMI-Mirror/scripts/start_mmi_mirror.sh" ] && \
         [ -f "${VOLUME}/MMI-Mirror/scripts/bounded_log.sh" ] && \
         [ -f "${VOLUME}/MMI-Mirror/scripts/restore_map.sh" ]; then
        RUNTIME_SCRIPTS="${VOLUME}/MMI-Mirror/scripts"
    else
        fail "MMI Mirror runtime scripts are missing from the SD-card"
    fi

    if ! artifact_sane "${JAR_SOURCE}"; then
        fail "Unified HMI JAR missing/invalid or looks like a pointer: ${JAR_SOURCE}"
    fi
    if ! artifact_sane "${RGI98_SOURCE}"; then
        fail "V2.2 RGI98 renderer missing/invalid or looks like a pointer: ${RGI98_SOURCE}"
    fi

    log "Unified HMI JAR fixed expected-size check: DISABLED (actual $(file_size "${JAR_SOURCE}") bytes)"
    log "RGI98 renderer package present: $(file_size "${RGI98_SOURCE}") bytes"
}

recover_stale_update() {
    rm -rf "${STAGE_DIR}" 2>/dev/null || true

    if [ ! -d "${ROLLBACK_DIR}" ]; then
        return
    fi

    if runtime_valid "${APP_TARGET}"; then
        log "Found stale runtime rollback from a completed update; removing it"
        rm -rf "${ROLLBACK_DIR}" || fail "Could not remove stale runtime rollback directory"
        return
    fi

    if runtime_valid "${ROLLBACK_DIR}"; then
        log "Recovering previous runtime from interrupted update"
        rm -rf "${APP_TARGET}" 2>/dev/null || true
        mv "${ROLLBACK_DIR}" "${APP_TARGET}" || fail "Could not recover previous runtime"
        sync || fail "sync failed after stale-update recovery"
        return
    fi

    fail "Ambiguous stale runtime rollback state; refusing to overwrite ${APP_TARGET}"
}

recover_stale_jar_transaction() {
    if [ ! -d "${JAR_TXN_DIR}" ]; then
        return
    fi
    if [ ! -f "${JAR_TXN_DIR}/active" ]; then
        log "Removing incomplete JAR transaction left before production replacement"
        rm -rf "${JAR_TXN_DIR}" || fail "Could not clean incomplete JAR transaction"
        return
    fi
    log "Detected interrupted previous JAR replacement; restoring pre-install carplay_hook.jar first"
    JAR_TXN_ACTIVE=1
    restore_carplay_jar_snapshot || fail "Could not recover interrupted carplay_hook.jar transaction"
}

recover_stale_renderer_transaction() {
    if [ ! -d "${RGI_RENDERER_TXN_DIR}" ]; then
        return
    fi
    if [ ! -f "${RGI_RENDERER_TXN_DIR}/active" ]; then
        log "Removing incomplete RGI renderer transaction left before production replacement"
        rm -rf "${RGI_RENDERER_TXN_DIR}" || fail "Could not clean incomplete RGI renderer transaction"
        return
    fi
    log "Detected interrupted previous RGI renderer replacement; restoring pre-install renderer first"
    RGI_RENDERER_TXN_ACTIVE=1
    restore_rgi_renderer_snapshot || fail "Could not recover interrupted RGI renderer transaction"
}

snapshot_carplay_jar() {
    rm -rf "${JAR_TXN_DIR}" 2>/dev/null || fail "Could not clear JAR transaction directory"
    mkdir -p "${JAR_TXN_DIR}" || fail "Could not create JAR transaction directory"

    if [ -f "${JAR_TARGET}" ]; then
        cp "${JAR_TARGET}" "${JAR_TXN_DIR}/carplay_hook.jar" || fail "Could not snapshot existing ${JAR_TARGET}"
        touch "${JAR_TXN_DIR}/present" || fail "Could not mark existing JAR snapshot"
    else
        touch "${JAR_TXN_DIR}/absent" || fail "Could not mark absent pre-install JAR"
    fi

    touch "${JAR_TXN_DIR}/active" || fail "Could not activate JAR transaction"
    JAR_TXN_ACTIVE=1
    log "Pre-install carplay_hook.jar state snapshotted"
}

snapshot_rgi_renderer() {
    rm -rf "${RGI_RENDERER_TXN_DIR}" 2>/dev/null || fail "Could not clear RGI renderer transaction directory"
    mkdir -p "${RGI_RENDERER_TXN_DIR}" || fail "Could not create RGI renderer transaction directory"

    if [ -f "${RGI_NATIVE_2}" ]; then
        cp "${RGI_NATIVE_2}" "${RGI_RENDERER_TXN_DIR}/maneuver_render" || fail "Could not snapshot existing RGI renderer"
        touch "${RGI_RENDERER_TXN_DIR}/present" || fail "Could not mark existing RGI renderer snapshot"
    else
        touch "${RGI_RENDERER_TXN_DIR}/absent" || fail "Could not mark absent pre-install RGI renderer"
    fi

    touch "${RGI_RENDERER_TXN_DIR}/active" || fail "Could not activate RGI renderer transaction"
    RGI_RENDERER_TXN_ACTIVE=1
    log "Pre-install RGI renderer state snapshotted"
}

trap 'fail "Installation interrupted by signal"' 1 2 15

log "===== MMI Mirror V2.2 / JAVA80 install/update started ====="
log "Firmware: ${VERSION}"
log "FAZIT: ${FAZIT}"
log "Runtime target: ${APP_TARGET}"
log "Unified HMI JAR source: ${JAR_SOURCE}"
log "Unified HMI JAR target: ${JAR_TARGET}"
log "RGI98 renderer source: ${RGI98_SOURCE}"
log "RGI renderer target: ${RGI_NATIVE_2}"
log "Stable RGI recovery source remains: ${VOLUME}/Toolbox/apps/carplay-rgi"

find_payload
log "Payload: ${BINARY_SOURCE}"
log "Runtime scripts: ${RUNTIME_SCRIPTS}"

# Stop any existing session before touching /mnt/app. In addition to the legacy
# runtime-directory/PID markers, detect a surviving Native process directly so
# upgrades remain safe even if an older session lost its PID file.
if [ -d "${APP_TARGET}" ] || [ -f /tmp/mmi-mirror-stage1.pid ] || mmi_process_running; then
    if [ -f "${SCRIPTDIR}/stop_mmi_mirror_toolbox.sh" ]; then
        log "Existing MMI Mirror installation/session detected; stopping BaseVideo before update"
        /bin/sh "${SCRIPTDIR}/stop_mmi_mirror_toolbox.sh" || fail "Could not stop existing MMI Mirror session"
        if mmi_process_running; then
            fail "mmi-mirror-display is still present after stop helper completed"
        fi
    else
        fail "Existing MMI Mirror installation detected but stop helper is missing"
    fi
fi

log "Mounting /mnt/app read-write"
mount -uw /mnt/app || fail "Could not mount /mnt/app read-write"
mkdir -p /mnt/app/root || fail "Could not create /mnt/app/root"
mkdir -p "${JAR_TARGET_DIR}" || fail "Could not create ${JAR_TARGET_DIR}"

if [ -e "${APP_TARGET}" ] && [ ! -d "${APP_TARGET}" ]; then
    fail "${APP_TARGET} exists but is not a directory"
fi

recover_stale_update
recover_stale_jar_transaction
recover_stale_renderer_transaction

RGI_NATIVE_COUNT=$(count_rgi_native_payloads)
if [ "${RGI_NATIVE_COUNT}" -eq 3 ]; then
    if ! artifact_sane "${STABLE_RGI_JAR}"; then
        fail "Complete RGI detected but stable recovery JAR is missing/invalid: ${STABLE_RGI_JAR}"
    fi
    if ! artifact_sane "${STABLE_RGI_RENDERER}"; then
        fail "Complete RGI detected but stable recovery renderer is missing/invalid: ${STABLE_RGI_RENDERER}"
    fi
    RGI98_DEPLOYED=1
elif [ "${RGI_NATIVE_COUNT}" -eq 0 ]; then
    RGI98_DEPLOYED=0
    log "RGI native payload state: absent (0/3); V2.2 RGI98 renderer will not be installed"
else
    RGI98_DEPLOYED=0
    log "WARNING: RGI native payload state is partial (${RGI_NATIVE_COUNT}/3); V2.2 will not replace maneuver_render"
fi

log "Building staged MMI runtime"
rm -rf "${STAGE_DIR}" || fail "Could not clean staging directory"
mkdir -p "${STAGE_DIR}/scripts" || fail "Could not create staging directory"

copy_checked "${BINARY_SOURCE}" "${STAGE_DIR}/mmi-mirror-display" 755
copy_checked "${RUNTIME_SCRIPTS}/start_mmi_mirror.sh" "${STAGE_DIR}/scripts/start_mmi_mirror.sh" 755
copy_checked "${RUNTIME_SCRIPTS}/bounded_log.sh" "${STAGE_DIR}/scripts/bounded_log.sh" 755
copy_checked "${RUNTIME_SCRIPTS}/restore_map.sh" "${STAGE_DIR}/scripts/restore_map.sh" 755

if [ -f "${APP_SOURCE}/config.local" ]; then
    copy_checked "${APP_SOURCE}/config.local" "${STAGE_DIR}/config.local" 644
    log "Installed config.local from SD-card"
elif [ -f "${APP_TARGET}/config.local" ]; then
    copy_checked "${APP_TARGET}/config.local" "${STAGE_DIR}/config.local" 644
    log "Preserved existing config.local"
fi

{
    echo "MMI Mirror V2.2 / JAVA80 final composite"
    echo "Firmware=${VERSION}"
    echo "FAZIT=${FAZIT}"
    echo "Installed=$(date)"
    echo "BinarySource=${BINARY_SOURCE}"
    echo "MMIDisplayable=3"
    echo "CompositeContext=80"
    echo "CompositeDisplayables=98,101,102,3"
    echo "ContextOwner=JAVA"
    echo "NativeContextRouting=removed"
    echo "UnifiedJarSource=${JAR_SOURCE}"
    echo "UnifiedJarTarget=${JAR_TARGET}"
    echo "UnifiedJarSize=$(file_size "${JAR_SOURCE}")"
    echo "UnifiedJarFixedExpectedSizeCheck=disabled"
    echo "RGI98Source=${RGI98_SOURCE}"
    echo "RGI98Target=${RGI_NATIVE_2}"
    echo "RGI98SHA256=0EF8A2A70E0AA02F595598960F35D82257F7367EB99ACF37566327038C5A9CD8"
    echo "RGI98Deployed=${RGI98_DEPLOYED}"
    echo "StableRGIRecovery=${VOLUME}/Toolbox/apps/carplay-rgi"
} > "${STAGE_DIR}/INSTALL_INFO.txt" || fail "Could not write INSTALL_INFO.txt"
chmod 644 "${STAGE_DIR}/INSTALL_INFO.txt" || fail "Could not chmod INSTALL_INFO.txt"

runtime_valid "${STAGE_DIR}" || fail "Staged runtime validation failed"

log "Committing staged MMI runtime"
rm -rf "${ROLLBACK_DIR}" 2>/dev/null || fail "Could not clear runtime rollback directory"
if [ -d "${APP_TARGET}" ]; then HAD_TARGET=1; else HAD_TARGET=0; fi
SWAP_STARTED=1

if [ "${HAD_TARGET}" -eq 1 ]; then
    mv "${APP_TARGET}" "${ROLLBACK_DIR}" || fail "Could not preserve currently installed runtime"
fi
mv "${STAGE_DIR}" "${APP_TARGET}" || fail "Could not activate staged runtime"
runtime_valid "${APP_TARGET}" || fail "Installed runtime validation failed"

export IPL_CONFIG_DIR="${IPL_CONFIG_DIR:-/etc/eso/production}"
export LD_LIBRARY_PATH="/mnt/app/eso/lib:/eso/lib:/mnt/app/root/lib-target:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
rm -f "${SELFTEST_LOG}" 2>/dev/null || true
if ! "${APP_TARGET}/mmi-mirror-display" --help > "${SELFTEST_LOG}" 2>&1; then
    log "Loader self-test failed; output follows:"
    cat "${SELFTEST_LOG}" 2>/dev/null || true
    fail "Installed binary could not execute --help"
fi
rm -f "${SELFTEST_LOG}" 2>/dev/null || true
log "Loader self-test passed (no display routing performed)"

cleanup_launcher_selftest
{
    echo '#!/bin/sh'
    echo 'exit 0'
} > "${LAUNCHER_SELFTEST_BIN}" || fail "Could not create launcher self-test stub"
chmod 755 "${LAUNCHER_SELFTEST_BIN}" || fail "Could not chmod launcher self-test stub"

if ! MMI_MIRROR_BIN="${LAUNCHER_SELFTEST_BIN}" \
     MMI_MIRROR_LOG="${LAUNCHER_SELFTEST_LOG}" \
     MMI_MIRROR_LOG_MAX_BYTES=65536 \
     /bin/sh "${APP_TARGET}/scripts/start_mmi_mirror.sh" \
     > "${LAUNCHER_SELFTEST_STDOUT}" 2>&1; then
    log "Launcher shell self-test failed; captured output follows:"
    cat "${LAUNCHER_SELFTEST_STDOUT}" 2>/dev/null || true
    cat "${LAUNCHER_SELFTEST_LOG}" 2>/dev/null || true
    fail "Installed launcher script failed zero-argument QNX shell self-test"
fi
cleanup_launcher_selftest
log "Launcher shell self-test passed (zero-argument QNX /bin/sh; no display routing performed)"

if [ "${RGI98_DEPLOYED}" -eq 1 ]; then
    log "Replacing complete stable RGI maneuver_render with V2.2 displayable98 renderer"
    snapshot_rgi_renderer
    rm -f "${RGI_NATIVE_2}.mmi-mirror.tmp" 2>/dev/null || true
    copy_checked "${RGI98_SOURCE}" "${RGI_NATIVE_2}.mmi-mirror.tmp" 755
    mv "${RGI_NATIVE_2}.mmi-mirror.tmp" "${RGI_NATIVE_2}" || fail "Could not activate V2.2 RGI98 renderer"
    log "V2.2 RGI98 renderer installed as ${RGI_NATIVE_2} ($(file_size "${RGI_NATIVE_2}") bytes)"
fi

log "Replacing LSD carplay_hook.jar with V2.2 Unified HMI candidate (fixed expected-size gate disabled)"
snapshot_carplay_jar
rm -f "${JAR_TARGET}.mmi-mirror.tmp" 2>/dev/null || true
copy_checked "${JAR_SOURCE}" "${JAR_TARGET}.mmi-mirror.tmp" 644
mv "${JAR_TARGET}.mmi-mirror.tmp" "${JAR_TARGET}" || fail "Could not activate V2.2 Unified HMI JAR"
log "V2.2 Unified HMI JAR installed as ${JAR_TARGET} ($(file_size "${JAR_TARGET}") bytes)"

sync || fail "sync failed"

rm -rf "${JAR_TXN_DIR}" || fail "Could not commit JAR transaction"
JAR_TXN_ACTIVE=0
if [ "${RGI_RENDERER_TXN_ACTIVE}" -eq 1 ]; then
    rm -rf "${RGI_RENDERER_TXN_DIR}" || fail "Could not commit RGI renderer transaction"
    RGI_RENDERER_TXN_ACTIVE=0
fi
SWAP_STARTED=0
rm -rf "${ROLLBACK_DIR}" 2>/dev/null || log "WARNING: stale runtime rollback directory could not be removed"

if remount_read_only; then
    log "/mnt/app remounted read-only"
else
    log "WARNING: installation succeeded but /mnt/app could not be remounted read-only"
fi
trap - 1 2 15

log "MMI Mirror V2.2 / JAVA80 final composite installed successfully."
if [ "${RGI98_DEPLOYED}" -eq 1 ]; then
    log "RGI complete (3/3): maneuver_render was transactionally migrated from stable displayable20 to V2.2 displayable98."
else
    log "RGI renderer was not modified because stable RGI was not complete (3/3)."
fi
log "Stable RGI recovery payloads in Toolbox/apps/carplay-rgi were not modified."
log "IMPORTANT: reboot/HMI restart is REQUIRED before starting MMI Mirror or judging RGI/ctx80 behavior."
log "Do not use RGI or Start MMI Mirror between this install and the reboot, because on-disk JAR/renderer have changed together."
log "After reboot use Green Menu 'Start MMI Mirror V2.2'."
log "Runtime logs: /tmp/mmi-mirror-display.log (+ .1 rotation)"
log "Install log: Backup/${VERSION}/MMIMirror/install_mmi_mirror.log"
log "===== MMI Mirror V2.2 / JAVA80 install/update finished ====="
exit 0
