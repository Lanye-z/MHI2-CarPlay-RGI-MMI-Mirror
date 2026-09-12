#!/bin/sh
# Disable future MMI Mirror V2.2 boot starts without stopping the current session.

export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH

if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
STARTUP="/etc/boot/startup.sh"
MARKER="${SCRIPTDIR}/.mmi_mirror_autostart"
BEGIN_MARK="# MMI MIRROR V2.2 AUTOSTART BEGIN"
STATUS="/tmp/mmi-mirror-autostart.status"

write_status() {
    {
        echo "version=mmi-mirror-autostart-v1"
        echo "state=$1"
        echo "detail=$2"
        echo "startup=${STARTUP}"
        echo "marker=${MARKER}"
        date
    } > "${STATUS}"
}

echo "MMI Mirror V2.2 AutoStart OFF: disabling future boot starts..."

# Remove the marker first so a boot runner that is currently waiting cannot
# start the runtime while startup.sh is being edited.
mount -uw /mnt/app 2>/dev/null || {
    write_status "FAILED" "Could not mount /mnt/app read-write"
    echo "Could not mount /mnt/app read-write"
    exit 1
}
rm -f "${MARKER}" || {
    mount -ur /mnt/app 2>/dev/null
    write_status "FAILED" "Could not remove the persistent marker"
    exit 1
}
sync
mount -ur /mnt/app 2>/dev/null || {
    write_status "FAILED" "Could not remount /mnt/app read-only"
    exit 1
}

if [ -f "${STARTUP}" ]; then
    mount -uw /mnt/system 2>/dev/null || {
        write_status "FAILED" "Marker removed, but /mnt/system could not be mounted read-write"
        echo "AutoStart is disabled by its marker, but the stale startup block could not be removed."
        exit 1
    }
    if grep -qF "${BEGIN_MARK}" "${STARTUP}" 2>/dev/null; then
        sed -i '/# MMI MIRROR V2.2 AUTOSTART BEGIN/,/# MMI MIRROR V2.2 AUTOSTART END/d' "${STARTUP}" || {
            mount -ur /mnt/system 2>/dev/null
            write_status "FAILED" "Marker removed, but the startup block could not be removed"
            exit 1
        }
    fi
    sync
    mount -ur /mnt/system 2>/dev/null || {
        write_status "FAILED" "Could not remount /mnt/system read-only"
        exit 1
    }
    if grep -qF "${BEGIN_MARK}" "${STARTUP}" 2>/dev/null; then
        write_status "FAILED" "Startup block remains after removal"
        echo "AutoStart startup block still exists after removal"
        exit 1
    fi
fi

rm -f /tmp/mmi-mirror-autostart-bootstrap.log /tmp/mmi-mirror-autostart.log 2>/dev/null || true
write_status "DISABLED" "Persistent marker and startup block removed"

echo "MMI Mirror V2.2 AutoStart OFF: disabled."
echo "The current session, if running, was not stopped; use Stop separately if needed."
exit 0
