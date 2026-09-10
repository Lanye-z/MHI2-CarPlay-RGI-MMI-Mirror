#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/media/gracenote/bin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH

if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )

. "${SCRIPTDIR}/util_info.sh"
. "${SCRIPTDIR}/util_mountsd.sh"
if [ -z "$VOLUME" ]; then
  echo "No SD-card found, quitting"
  exit 1
fi

HOOK_TARGET="/mnt/app/root/hooks"
JAR_TARGET="/mnt/app/eso/hmi/lsd/jars"
CONFIG_TARGET="/mnt/system/etc/eso/production"
SMARTPHONE_JSON="${CONFIG_TARGET}/smartphone_integrator.json"
DIO_JSON="${CONFIG_TARGET}/dio_manager.json"
BACKUPFOLDER="${VOLUME}/Backup/${VERSION}/CarPlayRGI"
LOGFILE="${BACKUPFOLDER}/uninstall_carplay_rgi.log"

# Keep green-menu messages visible on fd 3 while stdout/stderr is appended to the log.
exec 3>&1
mkdir -p "${BACKUPFOLDER}" || exit 1
touch "${LOGFILE}" || exit 1
exec >> "${LOGFILE}" 2>&1

log() {
  echo "$*"
  echo "$*" >&3
}

remount_read_only() {
  RO_RESULT=0
  mount -ur /mnt/app 2>/dev/null || RO_RESULT=1
  mount -ur /mnt/system 2>/dev/null || RO_RESULT=1
  return "${RO_RESULT}"
}

fail() {
  FAILURE_MESSAGE="$*"
  trap - 1 2 15
  log "ERROR: ${FAILURE_MESSAGE}"

  if remount_read_only; then
    log "Uninstall aborted. /mnt/app and /mnt/system were remounted read-only."
  else
    log "WARNING: Uninstall aborted and one or more filesystems could not be remounted read-only."
  fi

  log "Uninstall log: Backup/${VERSION}/CarPlayRGI/uninstall_carplay_rgi.log"
  exit 1
}

require_backup() {
  BACKUP="$1"
  if [ ! -f "${BACKUP}" ]; then
    fail "Missing original backup ${BACKUP}. No production files were changed."
  fi
}

restore_file() {
  FILENAME="$1"
  DEST="$2"
  SRC="${BACKUPFOLDER}/${FILENAME}"

  log "Restoring ${DEST} from ${SRC}"
  cp -v "${SRC}" "${DEST}" || fail "Could not restore ${DEST}"
  if [ -f "${DEST}" ]; then
    log "Restored ${DEST}"
  else
    fail "Restore verification failed for ${DEST}"
  fi
}

remove_component() {
  TARGET="$1"

  if [ -f "${TARGET}" ]; then
    log "Removing ${TARGET}"
    rm -fv "${TARGET}" || fail "Could not remove ${TARGET}"
    log "Removed ${TARGET}"
  else
    log "Component already absent: ${TARGET}"
  fi
}

verify_uninstall() {
  log "Verifying restored configuration files and removed components"

  if [ ! -f "${SMARTPHONE_JSON}" ]; then
    fail "Restored configuration is missing: ${SMARTPHONE_JSON}"
  fi
  if [ ! -f "${DIO_JSON}" ]; then
    fail "Restored configuration is missing: ${DIO_JSON}"
  fi

  for TARGET in \
    "${HOOK_TARGET}/libcarplay_hook.so" \
    "${HOOK_TARGET}/maneuver_render" \
    "${HOOK_TARGET}/flag_atlas.rgba" \
    "${JAR_TARGET}/carplay_hook.jar"
  do
    if [ -e "${TARGET}" ]; then
      fail "Component still exists after removal: ${TARGET}"
    fi
  done

  log "Uninstall verification passed"
}

trap 'fail "Uninstall interrupted by signal"' 1 2 15

log "===== CarPlay RGI uninstall started ====="
date
log "Firmware: ${VERSION}"
log "FAZIT: ${FAZIT}"
log "Backup: ${BACKUPFOLDER}"

log "Checking original configuration backups"
require_backup "${BACKUPFOLDER}/smartphone_integrator.json"
require_backup "${BACKUPFOLDER}/dio_manager.json"
log "Both original configuration backups are present"

log "Mounting /mnt/app and /mnt/system read-write"
mount -uw /mnt/app || fail "Could not mount /mnt/app read-write"
mount -uw /mnt/system || fail "Could not mount /mnt/system read-write"

restore_file "smartphone_integrator.json" "${SMARTPHONE_JSON}"
restore_file "dio_manager.json" "${DIO_JSON}"

log "Removing CarPlay RGI files"
remove_component "${HOOK_TARGET}/libcarplay_hook.so"
remove_component "${HOOK_TARGET}/maneuver_render"
remove_component "${HOOK_TARGET}/flag_atlas.rgba"
remove_component "${JAR_TARGET}/carplay_hook.jar"

verify_uninstall

log "Synchronizing filesystem changes"
sync || fail "sync failed"
sleep 1
remount_read_only || fail "Could not remount /mnt/app and /mnt/system read-only"
trap - 1 2 15

log "CarPlay Route Guidance Interface restored successfully."
log "Uninstall log: Backup/${VERSION}/CarPlayRGI/uninstall_carplay_rgi.log"
log "Please wait at least 30 seconds, then reboot the headunit."
log "===== CarPlay RGI uninstall finished ====="

exit 0
