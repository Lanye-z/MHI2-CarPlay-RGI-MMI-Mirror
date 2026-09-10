#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/media/gracenote/bin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH

RESULT=0

clear_runtime_log() {
  FILE="$1"

  if [ ! -f "${FILE}" ]; then
    echo "Runtime log already absent: ${FILE}"
    return
  fi

  if : > "${FILE}"; then
    echo "Cleared runtime log: ${FILE}"
  else
    echo "ERROR: Could not clear runtime log: ${FILE}"
    RESULT=1
  fi
}

echo "===== Clearing CarPlay RGI runtime logs ====="
clear_runtime_log "/tmp/carplay_hook.log"
clear_runtime_log "/tmp/maneuver_render.log"

if [ "${RESULT}" -eq 0 ]; then
  echo "CarPlay RGI runtime logs cleared successfully."
  echo "New runtime messages will continue to use the same log files."
else
  echo "CarPlay RGI runtime log clearing completed with errors."
fi

echo "===== CarPlay RGI runtime log clearing finished ====="
exit "${RESULT}"
