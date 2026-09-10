#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/media/gracenote/bin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH

# Emergency CarPlay RGI recovery.
# This script intentionally does NOT depend on firmware-version backups or on
# the current RGI installation state. It always attempts to restore the two
# known-good stock configuration files and remove all four RGI payload files.

if [ -d /net/mmx/fs/sda0/Toolbox ]; then
  VOLUME="/net/mmx/fs/sda0"
elif [ -d /net/mmx/fs/sdb0/Toolbox ]; then
  VOLUME="/net/mmx/fs/sdb0"
else
  echo "No Toolbox SD card found. Rescue payload is unavailable."
  exit 1
fi

RESCUE_SOURCE="${VOLUME}/Toolbox/apps/carplay-rgi/Rescue"
HOOK_TARGET="/mnt/app/root/hooks"
JAR_TARGET="/mnt/app/eso/hmi/lsd/jars"
CONFIG_TARGET="/mnt/system/etc/eso/production"
SMARTPHONE_JSON="${CONFIG_TARGET}/smartphone_integrator.json"
DIO_JSON="${CONFIG_TARGET}/dio_manager.json"
RESULT=0

mark_error() {
  echo "ERROR: $*"
  RESULT=1
}

restore_file() {
  SRC="$1"
  DEST="$2"
  TMP="${DEST}.carplay-rgi-rescue.tmp"

  rm -f "${TMP}" 2>/dev/null
  echo "Restoring ${DEST}"

  if ! cp -f "${SRC}" "${TMP}"; then
    mark_error "Could not copy rescue payload to ${TMP}"
    rm -f "${TMP}" 2>/dev/null
    return 1
  fi

  if ! chmod 644 "${TMP}"; then
    mark_error "Could not set permissions on ${TMP}"
    rm -f "${TMP}" 2>/dev/null
    return 1
  fi

  if ! mv -f "${TMP}" "${DEST}"; then
    mark_error "Could not replace ${DEST}"
    rm -f "${TMP}" 2>/dev/null
    return 1
  fi

  if [ ! -f "${DEST}" ]; then
    mark_error "Restore verification failed for ${DEST}"
    return 1
  fi

  if command -v cmp >/dev/null 2>&1; then
    if ! cmp "${SRC}" "${DEST}" >/dev/null 2>&1; then
      mark_error "Restored file does not match rescue payload: ${DEST}"
      return 1
    fi
  fi

  echo "Restored ${DEST}"
  return 0
}

remove_component() {
  TARGET="$1"

  if [ -e "${TARGET}" ]; then
    echo "Removing ${TARGET}"
  else
    echo "Already absent: ${TARGET}"
  fi

  if ! rm -f "${TARGET}"; then
    mark_error "Could not remove ${TARGET}"
    return 1
  fi

  if [ -e "${TARGET}" ]; then
    mark_error "Component still exists after removal: ${TARGET}"
    return 1
  fi

  return 0
}

remount_read_only() {
  mount -ur /mnt/app 2>/dev/null || mark_error "Could not remount /mnt/app read-only"
  mount -ur /mnt/system 2>/dev/null || mark_error "Could not remount /mnt/system read-only"
}

interrupted() {
  echo "Rescue interrupted. Synchronizing and attempting to restore read-only mounts."
  sync 2>/dev/null
  remount_read_only
  exit 1
}

trap 'interrupted' 1 2 15

echo "===== CarPlay RGI RESCUE started ====="
echo "Rescue source: ${RESCUE_SOURCE}"
echo "Saved RGI backups will NOT be used."

# The only hard precondition is that both known-good rescue files exist.
# Abort before touching production if the rescue payload itself is incomplete.
if [ ! -f "${RESCUE_SOURCE}/smartphone_integrator.json" ]; then
  echo "ERROR: Missing rescue payload: ${RESCUE_SOURCE}/smartphone_integrator.json"
  echo "Rescue aborted before changing production files."
  exit 1
fi
if [ ! -f "${RESCUE_SOURCE}/dio_manager.json" ]; then
  echo "ERROR: Missing rescue payload: ${RESCUE_SOURCE}/dio_manager.json"
  echo "Rescue aborted before changing production files."
  exit 1
fi

echo "Mounting /mnt/app and /mnt/system read-write"
mount -uw /mnt/app || mark_error "Could not mount /mnt/app read-write"
mount -uw /mnt/system || mark_error "Could not mount /mnt/system read-write"

# Always attempt BOTH stock-config restores, regardless of the current files,
# existing backups, or whether an RGI installation is complete/partial/broken.
restore_file "${RESCUE_SOURCE}/smartphone_integrator.json" "${SMARTPHONE_JSON}"
restore_file "${RESCUE_SOURCE}/dio_manager.json" "${DIO_JSON}"

# rm -f makes missing RGI components a valid state. Every target is attempted,
# so one missing file never prevents the other files from being removed.
echo "Removing all CarPlay RGI payload files"
remove_component "${HOOK_TARGET}/libcarplay_hook.so"
remove_component "${HOOK_TARGET}/maneuver_render"
remove_component "${HOOK_TARGET}/flag_atlas.rgba"
remove_component "${JAR_TARGET}/carplay_hook.jar"

echo "Synchronizing filesystem changes"
sync || mark_error "sync failed"
sleep 1

remount_read_only
trap - 1 2 15

if [ "${RESULT}" -eq 0 ]; then
  echo "CarPlay RGI rescue completed successfully."
  echo "Stock CarPlay configuration was force-restored from the Rescue folder."
  echo "All four RGI payload files are absent."
  echo "Please wait at least 30 seconds, then reboot the headunit."
else
  echo "CarPlay RGI rescue completed with one or more errors."
  echo "Review the messages above before rebooting."
fi

echo "===== CarPlay RGI RESCUE finished ====="
exit "${RESULT}"
