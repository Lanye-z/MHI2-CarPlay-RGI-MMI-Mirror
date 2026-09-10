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

LOGFOLDER="${VOLUME}/Backup/${VERSION}/CarPlayRGI"
RESULT=0

copy_runtime_log() {
  SOURCE="$1"
  FILENAME="$2"
  TARGET="${LOGFOLDER}/${FILENAME}"
  TMP="${TARGET}.carplay-rgi.tmp"

  if [ ! -f "${SOURCE}" ]; then
    echo "Missing runtime log: ${SOURCE}"
    echo "Previous collected copy, if present, was retained."
    RESULT=1
    return
  fi

  rm -f "${TMP}" 2>/dev/null
  if cp -v "${SOURCE}" "${TMP}" && \
     chmod 644 "${TMP}" && \
     mv "${TMP}" "${TARGET}"
  then
    echo "Saved ${SOURCE} to ${TARGET}"
  else
    rm -f "${TMP}" 2>/dev/null
    echo "ERROR: Could not save ${SOURCE}"
    RESULT=1
  fi
}

echo "===== Collecting CarPlay RGI runtime logs ====="
echo "Firmware: ${VERSION}"
echo "Destination: ${LOGFOLDER}"

mkdir -p "${LOGFOLDER}" || {
  echo "ERROR: Could not create ${LOGFOLDER}"
  exit 1
}

copy_runtime_log "/tmp/carplay_hook.log" "carplay_hook.log"
copy_runtime_log "/tmp/maneuver_render.log" "maneuver_render.log"

sync || {
  echo "ERROR: sync failed"
  RESULT=1
}

if [ "${RESULT}" -eq 0 ]; then
  echo "CarPlay RGI runtime logs collected successfully."
else
  echo "CarPlay RGI runtime log collection completed with errors."
fi

echo "===== CarPlay RGI runtime log collection finished ====="
exit "${RESULT}"
