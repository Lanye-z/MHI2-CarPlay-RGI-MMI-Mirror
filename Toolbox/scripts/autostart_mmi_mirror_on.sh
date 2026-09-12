#!/bin/sh
# Persistently enable MMI Mirror V2.2 at the proven DCIVIDEO/Kombi Map boot anchor.

export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH

if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
. "${SCRIPTDIR}/util_info.sh"
. "${SCRIPTDIR}/util_mountsd.sh"
[ -n "${VOLUME:-}" ] || { echo "No SD-card found"; exit 1; }

STARTUP="/etc/boot/startup.sh"
BOOT_ANCHOR="# DCIVIDEO: Kombi Map"
BOOT_BLOCK="/tmp/mmi_mirror_autostart.block"
MARKER="${SCRIPTDIR}/.mmi_mirror_autostart"
RUNNER="${SCRIPTDIR}/autostart_mmi_mirror_boot.sh"
RUNTIME="/mnt/app/root/mmi-mirror"
BEGIN_MARK="# MMI MIRROR V2.2 AUTOSTART BEGIN"
BACKUP="${VOLUME}/Backup/${VERSION}/MMIMirror/AutoStart"
STARTUP_BACKUP="${BACKUP}/startup.pre_mmi_mirror_autostart.sh"
CONFIG_STATUS="${BACKUP}/autostart_config_status.txt"

mkdir -p "${BACKUP}" || exit 1
[ -f "${STARTUP}" ] || { echo "Missing ${STARTUP}"; exit 1; }
[ -f "${RUNNER}" ] || { echo "Missing AutoStart boot runner: ${RUNNER}"; exit 1; }
[ -x "${RUNTIME}/mmi-mirror-display" ] || {
    echo "MMI Mirror V2.2 is not installed. Run Install/Update first."
    exit 1
}
[ -f "${RUNTIME}/scripts/start_mmi_mirror.sh" ] || {
    echo "Installed MMI Mirror launcher is missing. Run Install/Update again."
    exit 1
}

write_status() {
    {
        echo "version=mmi-mirror-autostart-config-v1"
        echo "state=$1"
        echo "detail=$2"
        echo "firmware=${VERSION}"
        echo "startup=${STARTUP}"
        echo "boot_anchor=${BOOT_ANCHOR}"
        echo "marker=${MARKER}"
        echo "runtime=${RUNTIME}"
        echo "requires_sd_card=0"
        date
    } > "${CONFIG_STATUS}"
    sync
}

remove_boot_block_best_effort() {
    mount -uw /mnt/system 2>/dev/null || return 1
    sed -i '/# MMI MIRROR V2.2 AUTOSTART BEGIN/,/# MMI MIRROR V2.2 AUTOSTART END/d' "${STARTUP}" 2>/dev/null
    sync
    mount -ur /mnt/system 2>/dev/null
}

if [ ! -f "${STARTUP_BACKUP}" ]; then
    cp "${STARTUP}" "${STARTUP_BACKUP}" || {
        write_status "FAILED" "Could not back up startup.sh"
        echo "Could not back up startup.sh"
        exit 1
    }
fi

mount -uw /mnt/system 2>/dev/null || {
    write_status "FAILED" "Could not mount /mnt/system read-write"
    echo "Could not mount /mnt/system read-write"
    exit 1
}

# Idempotently replace this project's block. Never restore the whole startup.sh,
# because other Toolbox features may also own independent boot modifications.
sed -i '/# MMI MIRROR V2.2 AUTOSTART BEGIN/,/# MMI MIRROR V2.2 AUTOSTART END/d' "${STARTUP}" || {
    mount -ur /mnt/system 2>/dev/null
    write_status "FAILED" "Could not remove a previous AutoStart block"
    exit 1
}

ANCHOR_COUNT=$(grep -cF "${BOOT_ANCHOR}" "${STARTUP}" 2>/dev/null)
if [ "${ANCHOR_COUNT}" != "1" ]; then
    mount -ur /mnt/system 2>/dev/null
    write_status "FAILED" "Expected exactly one boot anchor, found ${ANCHOR_COUNT}"
    echo "Expected exactly one '${BOOT_ANCHOR}' anchor; refusing an unsafe startup.sh edit."
    exit 1
fi

cat > "${BOOT_BLOCK}" <<'EOF'
# MMI MIRROR V2.2 AUTOSTART BEGIN
(
    N=0
    while [ "$N" -lt 120 ]; do
        if [ -f /mnt/app/eso/hmi/engdefs/scripts/mqb/.mmi_mirror_autostart ] && \
           [ -f /mnt/app/eso/hmi/engdefs/scripts/mqb/autostart_mmi_mirror_boot.sh ]; then
            /bin/sh /mnt/app/eso/hmi/engdefs/scripts/mqb/autostart_mmi_mirror_boot.sh
            exit $?
        fi
        /bin/sleep 1
        N=$((N + 1))
    done
    echo "MMI Mirror AutoStart bootstrap timed out waiting for /mnt/app"
) >/tmp/mmi-mirror-autostart-bootstrap.log 2>&1 &
# MMI MIRROR V2.2 AUTOSTART END
EOF

sed -i "/# DCIVIDEO: Kombi Map/r ${BOOT_BLOCK}" "${STARTUP}" || {
    rm -f "${BOOT_BLOCK}"
    mount -ur /mnt/system 2>/dev/null
    write_status "FAILED" "Could not inject AutoStart at the boot anchor"
    exit 1
}
rm -f "${BOOT_BLOCK}"
sync

BLOCK_COUNT=$(grep -cF "${BEGIN_MARK}" "${STARTUP}" 2>/dev/null)
ANCHOR_LINE=$(grep -nF "${BOOT_ANCHOR}" "${STARTUP}" 2>/dev/null | head -1 | cut -d: -f1)
BLOCK_LINE=$(grep -nF "${BEGIN_MARK}" "${STARTUP}" 2>/dev/null | head -1 | cut -d: -f1)
case "${ANCHOR_LINE}:${BLOCK_LINE}" in
    *[!0-9:]*|:|*:) LOCATION_OK=0 ;;
    *) [ "${BLOCK_LINE}" -gt "${ANCHOR_LINE}" ] && LOCATION_OK=1 || LOCATION_OK=0 ;;
esac

if [ "${BLOCK_COUNT}" != "1" ] || [ "${LOCATION_OK}" -ne 1 ]; then
    sed -i '/# MMI MIRROR V2.2 AUTOSTART BEGIN/,/# MMI MIRROR V2.2 AUTOSTART END/d' "${STARTUP}" 2>/dev/null
    sync
    mount -ur /mnt/system 2>/dev/null
    write_status "FAILED" "AutoStart block placement verification failed"
    echo "AutoStart block placement verification failed"
    exit 1
fi

{
    echo "anchor_line=${ANCHOR_LINE}"
    echo "block_line=${BLOCK_LINE}"
    echo "block_count=${BLOCK_COUNT}"
} > "${BACKUP}/startup_hook_location.txt"

mount -ur /mnt/system 2>/dev/null || {
    write_status "FAILED" "Could not remount /mnt/system read-only"
    echo "Could not remount /mnt/system read-only"
    exit 1
}

mount -uw /mnt/app 2>/dev/null || {
    remove_boot_block_best_effort
    write_status "FAILED" "Could not mount /mnt/app read-write"
    echo "Could not mount /mnt/app read-write"
    exit 1
}
touch "${MARKER}" || {
    mount -ur /mnt/app 2>/dev/null
    remove_boot_block_best_effort
    write_status "FAILED" "Could not create the persistent marker"
    echo "Could not create the persistent AutoStart marker"
    exit 1
}
sync
mount -ur /mnt/app 2>/dev/null || {
    write_status "FAILED" "Could not remount /mnt/app read-only"
    echo "Could not remount /mnt/app read-only"
    exit 1
}

write_status "ENABLED" "Boot hook installed at the DCIVIDEO/Kombi Map anchor"
echo "MMI Mirror V2.2 AutoStart ON: enabled."
echo "The installed runtime will start on the next complete MMI boot."
echo "The SD card is not required for boot-time execution after installation."
echo "Use 'AutoStart OFF' before removing Toolbox or changing the runtime."
exit 0
