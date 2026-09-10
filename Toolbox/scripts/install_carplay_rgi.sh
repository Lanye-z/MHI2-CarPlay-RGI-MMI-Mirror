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

APP_SOURCE="${VOLUME}/Toolbox/apps/carplay-rgi"
HOOK_TARGET="/mnt/app/root/hooks"
JAR_TARGET="/mnt/app/eso/hmi/lsd/jars"
CONFIG_TARGET="/mnt/system/etc/eso/production"
SMARTPHONE_JSON="${CONFIG_TARGET}/smartphone_integrator.json"
DIO_JSON="${CONFIG_TARGET}/dio_manager.json"
BACKUPFOLDER="${VOLUME}/Backup/${VERSION}/CarPlayRGI"
LOGFILE="${BACKUPFOLDER}/install_carplay_rgi.log"
TXN_DIR="${BACKUPFOLDER}/.install_transaction"
PRELOAD_VALUE="LD_PRELOAD=/mnt/app/root/hooks/libcarplay_hook.so"
TXN_ACTIVE=0
ROLLING_BACK=0
INSTALL_MODE="unknown"

# Keep green-menu messages visible on fd 3 while stdout/stderr is appended to the log.
exec 3>&1
mkdir -p "${BACKUPFOLDER}" || exit 1
touch "${BACKUPFOLDER}/DONT_TOUCH_ANYTHING_HERE" || exit 1
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

cleanup_incomplete_transaction() {
  if [ -d "${TXN_DIR}" ] && [ ! -f "${TXN_DIR}/active" ]; then
    rm -rf "${TXN_DIR}" 2>/dev/null
  fi
}

restore_snapshot_file() {
  LABEL="$1"
  TARGET="$2"
  MODE="$3"

  rm -f "${TARGET}.carplay-rgi.tmp" "${TARGET}.carplay-rgi.rollback.tmp" 2>/dev/null

  if [ -f "${TXN_DIR}/${LABEL}.present" ]; then
    if cp "${TXN_DIR}/${LABEL}" "${TARGET}.carplay-rgi.rollback.tmp" && \
       chmod "${MODE}" "${TARGET}.carplay-rgi.rollback.tmp" && \
       mv "${TARGET}.carplay-rgi.rollback.tmp" "${TARGET}"
    then
      log "Rollback restored ${TARGET}"
      return 0
    fi
    log "ROLLBACK ERROR: Could not restore ${TARGET}"
    return 1
  fi

  if rm -f "${TARGET}"; then
    log "Rollback removed newly installed ${TARGET}"
    return 0
  fi

  log "ROLLBACK ERROR: Could not remove ${TARGET}"
  return 1
}

restore_backup_artifact() {
  LABEL="$1"
  TARGET="$2"

  rm -f "${TARGET}.carplay-rgi.tmp" 2>/dev/null
  if [ -f "${TXN_DIR}/${LABEL}.present" ]; then
    if cp "${TXN_DIR}/${LABEL}" "${TARGET}.carplay-rgi.tmp" && mv "${TARGET}.carplay-rgi.tmp" "${TARGET}"; then
      log "Rollback restored ${TARGET}"
      return 0
    fi
    log "ROLLBACK ERROR: Could not restore ${TARGET}"
    return 1
  fi

  if rm -f "${TARGET}"; then
    return 0
  fi

  log "ROLLBACK ERROR: Could not remove ${TARGET}"
  return 1
}

rollback_installation() {
  if [ "${ROLLING_BACK}" -eq 1 ]; then
    return 1
  fi

  ROLLING_BACK=1
  trap - 1 2 15
  ROLLBACK_RESULT=0
  log "Rollback started"

  mount -uw /mnt/app 2>/dev/null || ROLLBACK_RESULT=1
  mount -uw /mnt/system 2>/dev/null || ROLLBACK_RESULT=1

  restore_snapshot_file "smartphone_integrator.json" "${SMARTPHONE_JSON}" 644 || ROLLBACK_RESULT=1
  restore_snapshot_file "dio_manager.json" "${DIO_JSON}" 644 || ROLLBACK_RESULT=1
  restore_snapshot_file "libcarplay_hook.so" "${HOOK_TARGET}/libcarplay_hook.so" 755 || ROLLBACK_RESULT=1
  restore_snapshot_file "maneuver_render" "${HOOK_TARGET}/maneuver_render" 755 || ROLLBACK_RESULT=1
  restore_snapshot_file "flag_atlas.rgba" "${HOOK_TARGET}/flag_atlas.rgba" 644 || ROLLBACK_RESULT=1
  restore_snapshot_file "carplay_hook.jar" "${JAR_TARGET}/carplay_hook.jar" 644 || ROLLBACK_RESULT=1
  restore_backup_artifact "smartphone_integrator_new.json" "${BACKUPFOLDER}/smartphone_integrator_new.json" || ROLLBACK_RESULT=1
  restore_backup_artifact "dio_manager_new.json" "${BACKUPFOLDER}/dio_manager_new.json" || ROLLBACK_RESULT=1

  if [ -f "${TXN_DIR}/hook_dir_absent" ]; then
    rmdir "${HOOK_TARGET}" 2>/dev/null || true
  fi
  if [ -f "${TXN_DIR}/jar_dir_absent" ]; then
    rmdir "${JAR_TARGET}" 2>/dev/null || true
  fi

  sync 2>/dev/null || ROLLBACK_RESULT=1
  remount_read_only || ROLLBACK_RESULT=1

  if [ "${ROLLBACK_RESULT}" -eq 0 ]; then
    TXN_ACTIVE=0
    rm -rf "${TXN_DIR}" 2>/dev/null || true
    log "Rollback completed; pre-install state restored"
  else
    log "ROLLBACK INCOMPLETE: Transaction snapshot retained at ${TXN_DIR}"
  fi

  ROLLING_BACK=0
  return "${ROLLBACK_RESULT}"
}

fail() {
  FAILURE_MESSAGE="$*"
  log "ERROR: ${FAILURE_MESSAGE}"

  if [ "${TXN_ACTIVE}" -eq 1 ] || [ -f "${TXN_DIR}/active" ]; then
    rollback_installation
    ROLLBACK_STATUS=$?
  else
    ROLLBACK_STATUS=0
    cleanup_incomplete_transaction
    remount_read_only 2>/dev/null || true
  fi

  if [ "${ROLLBACK_STATUS}" -eq 0 ]; then
    log "Installation aborted safely. See ${LOGFILE}"
  else
    log "Installation aborted, but rollback was incomplete. Do not reboot; inspect ${LOGFILE} and ${TXN_DIR}"
  fi
  exit 1
}

require_file() {
  if [ ! -f "$1" ]; then
    fail "Missing $1"
  fi
}

snapshot_file() {
  TARGET="$1"
  LABEL="$2"

  if [ -f "${TARGET}" ]; then
    cp "${TARGET}" "${TXN_DIR}/${LABEL}" || fail "Could not snapshot ${TARGET}"
    touch "${TXN_DIR}/${LABEL}.present" || fail "Could not mark snapshot ${LABEL}"
  fi
}

begin_transaction() {
  log "Creating pre-install transaction snapshot"
  mkdir "${TXN_DIR}" || fail "Could not create transaction directory ${TXN_DIR}"

  snapshot_file "${SMARTPHONE_JSON}" "smartphone_integrator.json"
  snapshot_file "${DIO_JSON}" "dio_manager.json"
  snapshot_file "${HOOK_TARGET}/libcarplay_hook.so" "libcarplay_hook.so"
  snapshot_file "${HOOK_TARGET}/maneuver_render" "maneuver_render"
  snapshot_file "${HOOK_TARGET}/flag_atlas.rgba" "flag_atlas.rgba"
  snapshot_file "${JAR_TARGET}/carplay_hook.jar" "carplay_hook.jar"
  snapshot_file "${BACKUPFOLDER}/smartphone_integrator_new.json" "smartphone_integrator_new.json"
  snapshot_file "${BACKUPFOLDER}/dio_manager_new.json" "dio_manager_new.json"

  if [ ! -d "${HOOK_TARGET}" ]; then
    touch "${TXN_DIR}/hook_dir_absent" || fail "Could not record hooks directory state"
  fi
  if [ ! -d "${JAR_TARGET}" ]; then
    touch "${TXN_DIR}/jar_dir_absent" || fail "Could not record jars directory state"
  fi

  touch "${TXN_DIR}/active" || fail "Could not activate transaction snapshot"
  TXN_ACTIVE=1
  log "Transaction snapshot ready"
}

recover_stale_transaction() {
  if [ ! -d "${TXN_DIR}" ]; then
    return
  fi

  if [ -f "${TXN_DIR}/committed" ]; then
    log "Removing transaction snapshot left after a completed installation"
    rm -rf "${TXN_DIR}" || fail "Could not remove completed transaction snapshot"
    return
  fi

  if [ ! -f "${TXN_DIR}/active" ]; then
    log "Removing incomplete transaction snapshot left before any production change"
    rm -rf "${TXN_DIR}" || fail "Could not remove incomplete transaction snapshot"
    return
  fi

  log "Detected an interrupted previous installation; restoring its pre-install state first"
  TXN_ACTIVE=1
  if ! rollback_installation; then
    fail "Could not recover interrupted previous installation"
  fi
  trap 'fail "Installation interrupted by signal"' 1 2 15
}

backup_file() {
  SRC="$1"
  FILENAME=$(basename "$SRC")

  if [ -f "${BACKUPFOLDER}/${FILENAME}" ]; then
    log "Original backup already exists for ${FILENAME}. Skipping..."
  else
    log "Backing up original ${SRC}"
    cp -v "${SRC}" "${BACKUPFOLDER}/${FILENAME}" || fail "Could not back up ${SRC}"
  fi
}

preload_count() {
  FILE="$1"
  awk -v value="${PRELOAD_VALUE}" '
    { line=$0; while ((pos=index(line, value)) > 0) { count++; line=substr(line, pos+length(value)) } }
    END { print count+0 }
  ' "${FILE}"
}

# Output: <carplay object count> <carplay envs array count> <DIO env marker count> <LD_PRELOAD count in carplay.envs>
carplay_env_stats() {
  FILE="$1"
  awk -v needle="IPL_CONFIG_DIR_DIO_MANAGER=/etc/eso/production" -v value="${PRELOAD_VALUE}" '
    function brace_delta(s, start,    i,c,q,e,d) {
      for (i=start; i<=length(s); i++) {
        c=substr(s,i,1)
        if (q) { if (e) e=0; else if (c=="\\") e=1; else if (c=="\"") q=0 }
        else if (c=="\"") q=1
        else if (c=="{") d++
        else if (c=="}") d--
      }
      return d
    }
    function scan_array(s, start,    i,c,q,e,part,pos) {
      for (i=start; i<=length(s); i++) {
        c=substr(s,i,1)
        if (q) { if (e) e=0; else if (c=="\\") e=1; else if (c=="\"") q=0 }
        else if (c=="\"") q=1
        else if (c=="[") array_depth++
        else if (c=="]") { array_depth--; if (array_depth==0) { env_active=0; return i } }
      }
      return 0
    }
    function count_values(s,    part,pos) {
      part=s
      while ((pos=index(part, needle)) > 0) { needle_count++; part=substr(part,pos+length(needle)) }
      part=s
      while ((pos=index(part, value)) > 0) { value_count++; part=substr(part,pos+length(value)) }
    }
    /^[ \t]*#/ { next }
    {
      line=$0
      if (!carplay && !carplay_pending) {
        key_pos=index(line,"\"carplay\"")
        if (key_pos > 0 && substr(line,key_pos+length("\"carplay\"")) ~ /^[ \t]*:/) {
          carplay_pending=1
          object_count++
          search_start=key_pos
        }
      } else search_start=1

      if (carplay_pending && !carplay) {
        open_rel=index(substr(line,search_start),"{")
        if (open_rel > 0) {
          object_start=search_start+open_rel-1
          carplay=1
          carplay_pending=0
          object_depth=0
        }
      } else object_start=1

      if (carplay) {
        if (!env_active && !env_pending) {
          env_pos=index(substr(line,object_start),"\"envs\"")
          if (env_pos > 0 && substr(line,object_start+env_pos-1+length("\"envs\"")) ~ /^[ \t]*:/) {
            env_pending=1
            env_count++
            env_search=object_start+env_pos-1
          }
        } else env_search=1

        if (env_pending && !env_active) {
          open_rel=index(substr(line,env_search),"[")
          if (open_rel > 0) {
            array_start=env_search+open_rel-1
            env_active=1
            env_pending=0
            array_depth=0
          }
        } else if (env_active) array_start=1

        if (env_active) {
          close_pos=scan_array(line,array_start)
          if (close_pos > 0) count_values(substr(line,array_start,close_pos-array_start+1))
          else count_values(substr(line,array_start))
        }

        object_depth += brace_delta(line,object_start)
        if (object_depth==0) { carplay=0; object_start=1 }
      }
    }
    END { print object_count+0, env_count+0, needle_count+0, value_count+0 }
  ' "${FILE}"
}

# Output: <matching array count> <value count inside matching arrays>
array_stats() {
  FILE="$1"
  KEY="$2"
  VALUE="$3"
  awk -v key="\"${KEY}\"" -v value="\"${VALUE}\"" '
    function scan_array(s, start,    i,c,q,e) {
      for (i=start; i<=length(s); i++) {
        c=substr(s,i,1)
        if (q) { if (e) e=0; else if (c=="\\") e=1; else if (c=="\"") q=0 }
        else if (c=="\"") q=1
        else if (c=="[") depth++
        else if (c=="]") { depth--; if (depth==0) { active=0; return i } }
      }
      return 0
    }
    function count_value(s,    part,pos) {
      part=s
      while ((pos=index(part,value)) > 0) { values++; part=substr(part,pos+length(value)) }
    }
    /^[ \t]*#/ { next }
    {
      line=$0
      if (!active && !pending) {
        key_pos=index(line,key)
        if (key_pos > 0 && substr(line,key_pos+length(key)) ~ /^[ \t]*:/) { pending=1; arrays++; search=key_pos }
      } else search=1
      if (pending && !active) {
        open_rel=index(substr(line,search),"[")
        if (open_rel > 0) { start=search+open_rel-1; active=1; pending=0; depth=0 }
      } else if (active) start=1
      if (active) {
        close_at=scan_array(line,start)
        if (close_at > 0) count_value(substr(line,start,close_at-start+1))
        else count_value(substr(line,start))
      }
    }
    END { print arrays+0, values+0 }
  ' "${FILE}"
}

preflight_configuration() {
  log "Preflight-checking production configuration"

  set -- $(carplay_env_stats "${SMARTPHONE_JSON}")
  CARPLAY_OBJECTS=$1
  CARPLAY_ENVS=$2
  DIO_ENV_COUNT=$3
  PRELOAD_VALID=$4
  PRELOAD_TOTAL=$(preload_count "${SMARTPHONE_JSON}")

  if [ "${CARPLAY_OBJECTS}" -ne 1 ] || [ "${CARPLAY_ENVS}" -ne 1 ] || [ "${DIO_ENV_COUNT}" -ne 1 ]; then
    fail "Expected exactly one carplay.envs array containing the DIO manager environment marker"
  fi
  if [ "${PRELOAD_TOTAL}" -gt 1 ] || [ "${PRELOAD_TOTAL}" -ne "${PRELOAD_VALID}" ]; then
    fail "Malformed or duplicate LD_PRELOAD detected outside carplay.envs"
  fi

  CONFIG_MARKER_COUNT="${PRELOAD_VALID}"
  for ITEM in \
    "MessagesSentByAccessory:0x5200" \
    "MessagesSentByAccessory:0x5203" \
    "MessagesReceivedFromDevice:0x5201" \
    "MessagesReceivedFromDevice:0x5202" \
    "MessagesReceivedFromDevice:0x5204"
  do
    KEY=${ITEM%%:*}
    VALUE=${ITEM#*:}
    set -- $(array_stats "${DIO_JSON}" "${KEY}" "${VALUE}")
    ARRAY_COUNT=$1
    VALUE_COUNT=$2
    if [ "${ARRAY_COUNT}" -ne 1 ]; then
      fail "Expected exactly one ${KEY} array"
    fi
    if [ "${VALUE_COUNT}" -gt 1 ]; then
      fail "Duplicate ${VALUE} detected in ${KEY}"
    fi
    CONFIG_MARKER_COUNT=$((CONFIG_MARKER_COUNT + VALUE_COUNT))
  done

  if [ "${CONFIG_MARKER_COUNT}" -eq 0 ]; then
    INSTALL_MODE="first"
    log "Configuration state: clean first installation"
  elif [ "${CONFIG_MARKER_COUNT}" -eq 6 ]; then
    INSTALL_MODE="repeat"
    if [ ! -f "${BACKUPFOLDER}/smartphone_integrator.json" ] || [ ! -f "${BACKUPFOLDER}/dio_manager.json" ]; then
      fail "Complete RGI configuration found but original backups are missing; refusing unsafe repeat installation"
    fi
    log "Configuration state: complete previous installation; safe repeat installation"
  else
    fail "Partial CarPlay RGI configuration detected (${CONFIG_MARKER_COUNT}/6 markers). Restore both original JSON files before retrying"
  fi

  log "Production configuration preflight passed"
}

validate_original_backups() {
  require_file "${BACKUPFOLDER}/smartphone_integrator.json"
  require_file "${BACKUPFOLDER}/dio_manager.json"

  set -- $(carplay_env_stats "${BACKUPFOLDER}/smartphone_integrator.json")
  if [ "$1" -ne 1 ] || [ "$2" -ne 1 ] || [ "$3" -ne 1 ] || [ "$4" -ne 0 ] || [ "$(preload_count "${BACKUPFOLDER}/smartphone_integrator.json")" -ne 0 ]; then
    fail "Original smartphone_integrator.json backup is structurally invalid or already contains CarPlay RGI LD_PRELOAD"
  fi

  for ITEM in \
    "MessagesSentByAccessory:0x5200" \
    "MessagesSentByAccessory:0x5203" \
    "MessagesReceivedFromDevice:0x5201" \
    "MessagesReceivedFromDevice:0x5202" \
    "MessagesReceivedFromDevice:0x5204"
  do
    KEY=${ITEM%%:*}
    VALUE=${ITEM#*:}
    set -- $(array_stats "${BACKUPFOLDER}/dio_manager.json" "${KEY}" "${VALUE}")
    if [ "$1" -ne 1 ] || [ "$2" -ne 0 ]; then
      fail "Original dio_manager.json backup is invalid or already contains ${VALUE} in ${KEY}"
    fi
  done

  log "Original backup validation passed"
}

patch_smartphone_integrator() {
  set -- $(carplay_env_stats "${SMARTPHONE_JSON}")
  if [ "$4" -eq 1 ]; then
    log "carplay.envs already contains CarPlay RGI LD_PRELOAD. Skipping..."
    return
  fi

  log "Adding CarPlay RGI LD_PRELOAD to carplay.envs"
  TMP="${SMARTPHONE_JSON}.carplay-rgi.tmp"

  awk -v value="${PRELOAD_VALUE}" '
    function brace_delta(s, start,    i,c,q,e,d) {
      for (i=start; i<=length(s); i++) {
        c=substr(s,i,1)
        if (q) { if (e) e=0; else if (c=="\\") e=1; else if (c=="\"") q=0 }
        else if (c=="\"") q=1
        else if (c=="{") d++
        else if (c=="}") d--
      }
      return d
    }
    function find_close(s, start,    i,c,q,e) {
      for (i=start; i<=length(s); i++) {
        c=substr(s,i,1)
        if (q) { if (e) e=0; else if (c=="\\") e=1; else if (c=="\"") q=0 }
        else if (c=="\"") q=1
        else if (c=="[") depth++
        else if (c=="]") { depth--; if (depth==0) return i }
      }
      return 0
    }
    function leading_ws(s) { match(s,/^[ \t]*/); return substr(s,1,RLENGTH) }
    function nonblank(s) { return s ~ /[^ \t]/ }
    function element_line(s, first,    part,p) {
      part=s
      if (first) { p=index(part,"["); if (p > 0) part=substr(part,p+1) }
      return index(part,"\"") > 0
    }
    function add_comma(s,    t,ws) {
      match(s,/[ \t]*$/); ws=substr(s,RSTART); t=substr(s,1,RSTART-1)
      if (t !~ /,$/) t=t ","
      return t ws
    }
    function flush_multiline(close_at,    prefix,suffix,close_ws,content_n,last,i,indent) {
      prefix=substr(buf[buf_n],1,close_at-1)
      suffix=substr(buf[buf_n],close_at)
      close_ws=leading_ws(buf[buf_n])
      if (nonblank(prefix)) {
        buf[buf_n]=prefix
        content_n=buf_n
        close_line=close_ws suffix
      } else {
        content_n=buf_n-1
        close_line=buf[buf_n]
      }
      last=0
      for (i=content_n; i>=1; i--) {
        if (element_line(buf[i],i==1)) { last=i; break }
      }
      if (last > 0) {
        buf[last]=add_comma(buf[last])
        indent=leading_ws(buf[last])
        if (last==1) indent=close_ws "    "
      } else indent=close_ws "    "
      for (i=1; i<=content_n; i++) print buf[i]
      print indent "\"" value "\""
      print close_line
      delete buf
      buf_n=0
    }
    {
      line=$0
      if (active && multiline) {
        buf[++buf_n]=line
        if (line !~ /^[ \t]*#/) {
          close_at=find_close(line,1)
          if (close_at > 0) {
            flush_multiline(close_at)
            active=0
            multiline=0
            patched++
          }
        }
        next
      }
      if (line ~ /^[ \t]*#/) { print line; next }

      if (!carplay && !carplay_pending) {
        key_pos=index(line,"\"carplay\"")
        if (key_pos > 0 && substr(line,key_pos+length("\"carplay\"")) ~ /^[ \t]*:/) { carplay_pending=1; search_start=key_pos }
      } else search_start=1
      if (carplay_pending && !carplay) {
        open_rel=index(substr(line,search_start),"{")
        if (open_rel > 0) { object_start=search_start+open_rel-1; carplay=1; carplay_pending=0; object_depth=0 }
      } else object_start=1

      if (carplay) {
        if (!active && !pending) {
          env_pos=index(substr(line,object_start),"\"envs\"")
          if (env_pos > 0 && substr(line,object_start+env_pos-1+length("\"envs\"")) ~ /^[ \t]*:/) { pending=1; env_search=object_start+env_pos-1 }
        } else env_search=1
        if (pending && !active) {
          open_rel=index(substr(line,env_search),"[")
          if (open_rel > 0) {
            start=env_search+open_rel-1
            active=1
            pending=0
            depth=0
            close_at=find_close(line,start)
            if (close_at > 0) {
              line=substr(line,1,close_at-1) ", \"" value "\"" substr(line,close_at)
              active=0
              patched++
            } else {
              multiline=1
              buf[++buf_n]=line
              next
            }
          }
        }
        object_depth += brace_delta(line,object_start)
        if (object_depth==0) carplay=0
      }
      print line
    }
    END { if (patched != 1 || active || pending) exit 2 }
  ' "${SMARTPHONE_JSON}" > "${TMP}" || fail "Could not patch carplay.envs"

  set -- $(carplay_env_stats "${TMP}")
  if [ "$1" -ne 1 ] || [ "$2" -ne 1 ] || [ "$3" -ne 1 ] || [ "$4" -ne 1 ] || [ "$(preload_count "${TMP}")" -ne 1 ]; then
    fail "carplay.envs verification failed before replacing smartphone_integrator.json"
  fi

  chmod 644 "${TMP}" || fail "Could not chmod patched smartphone_integrator.json"
  mv "${TMP}" "${SMARTPHONE_JSON}" || fail "Could not install patched smartphone_integrator.json"
}

dio_comment_count() {
  FILE="$1"
  TEXT="$2"
  awk -v text="${TEXT}" '
    /^[ \t]*#/ && index($0,text) { count++ }
    END { print count+0 }
  ' "${FILE}"
}

verify_dio_comments() {
  FILE="$1"
  for COMMENT in \
    "0x5200/* StartRouteGuidanceUpdates */" \
    "0x5203/* StopRouteGuidanceUpdates */" \
    "0x5201/* RouteGuidanceUpdate */" \
    "0x5202/* RouteGuidanceManeuverUpdate */" \
    "0x5204/* RouteGuidanceLaneGuidanceInformation */"
  do
    if [ "$(dio_comment_count "${FILE}" "${COMMENT}")" -ne 1 ]; then
      return 1
    fi
  done
  return 0
}

patch_dio_manager() {
  log "Adding all CarPlay RGI message IDs and definitions to dio_manager.json in one pass"
  TMP="${DIO_JSON}.carplay-rgi.tmp"

  C5200=$(dio_comment_count "${DIO_JSON}" "0x5200/* StartRouteGuidanceUpdates */")
  C5203=$(dio_comment_count "${DIO_JSON}" "0x5203/* StopRouteGuidanceUpdates */")
  C5201=$(dio_comment_count "${DIO_JSON}" "0x5201/* RouteGuidanceUpdate */")
  C5202=$(dio_comment_count "${DIO_JSON}" "0x5202/* RouteGuidanceManeuverUpdate */")
  C5204=$(dio_comment_count "${DIO_JSON}" "0x5204/* RouteGuidanceLaneGuidanceInformation */")

  awk -v c5200="${C5200}" -v c5203="${C5203}" -v c5201="${C5201}" -v c5202="${C5202}" -v c5204="${C5204}" '
    function find_close(s, start,    i,c,q,e) {
      for (i=start; i<=length(s); i++) {
        c=substr(s,i,1)
        if (q) { if (e) e=0; else if (c=="\\") e=1; else if (c=="\"") q=0 }
        else if (c=="\"") { q=1; has_element=1 }
        else if (c=="[") depth++
        else if (c=="]") { depth--; if (depth==0) return i }
      }
      return 0
    }
    function leading_ws(s) { match(s,/^[ \t]*/); return substr(s,1,RLENGTH) }
    function nonblank(s) { return s ~ /[^ \t]/ }
    function element_line(s, first,    part,p) {
      part=s
      if (first) { p=index(part,"["); if (p > 0) part=substr(part,p+1) }
      return index(part,"\"") > 0
    }
    function add_comma(s,    t,ws) {
      match(s,/[ \t]*$/); ws=substr(s,RSTART); t=substr(s,1,RSTART-1)
      if (t !~ /,$/) t=t ","
      return t ws
    }
    function flush_multiline(close_at, values,    prefix,suffix,close_ws,content_n,last,i,indent,n,v) {
      prefix=substr(buf[buf_n],1,close_at-1)
      suffix=substr(buf[buf_n],close_at)
      close_ws=leading_ws(buf[buf_n])
      if (nonblank(prefix)) {
        buf[buf_n]=prefix
        content_n=buf_n
        close_line=close_ws suffix
      } else {
        content_n=buf_n-1
        close_line=buf[buf_n]
      }
      last=0
      for (i=content_n; i>=1; i--) {
        if (element_line(buf[i],i==1)) { last=i; break }
      }
      if (last > 0) {
        buf[last]=add_comma(buf[last])
        indent=leading_ws(buf[last])
        if (last==1) indent=close_ws "    "
      } else indent=close_ws "    "
      for (i=1; i<=content_n; i++) print buf[i]
      n=split(values,new_value," ")
      for (i=1; i<=n; i++) {
        v=new_value[i]
        if (i<n) print indent "\"" v "\"," 
        else print indent "\"" v "\""
      }
      print close_line
      delete buf
      delete new_value
      buf_n=0
    }
    {
      line=$0
      if (active && multiline) {
        buf[++buf_n]=line
        if (line !~ /^[ \t]*#/) {
          close_at=find_close(line,1)
          if (close_at > 0) {
            if (mode=="sent") values="0x5200 0x5203"
            else values="0x5201 0x5202 0x5204"
            flush_multiline(close_at,values)
            active=0
            multiline=0
            if (mode=="sent") sent_done++
            else recv_done++
            mode=""
          }
        }
        next
      }
      if (line ~ /^[ \t]*#/) { print line; next }

      if (!active && !pending) {
        sent_pos=index(line,"\"MessagesSentByAccessory\"")
        recv_pos=index(line,"\"MessagesReceivedFromDevice\"")
        if (sent_pos > 0 && substr(line,sent_pos+length("\"MessagesSentByAccessory\"")) ~ /^[ \t]*:/) {
          indent=leading_ws(line)
          if (c5200==0) print indent "# , 0x5200/* StartRouteGuidanceUpdates */"
          if (c5203==0) print indent "# , 0x5203/* StopRouteGuidanceUpdates */"
          mode="sent"; pending=1; search=sent_pos
        }
        else if (recv_pos > 0 && substr(line,recv_pos+length("\"MessagesReceivedFromDevice\"")) ~ /^[ \t]*:/) {
          indent=leading_ws(line)
          if (c5201==0) print indent "# 0x5201/* RouteGuidanceUpdate */"
          if (c5202==0) print indent "# 0x5202/* RouteGuidanceManeuverUpdate */"
          if (c5204==0) print indent "# 0x5204/* RouteGuidanceLaneGuidanceInformation */"
          mode="recv"; pending=1; search=recv_pos
        }
      } else search=1
      if (pending && !active) {
        open_rel=index(substr(line,search),"[")
        if (open_rel > 0) {
          start=search+open_rel-1
          active=1
          pending=0
          depth=0
          has_element=0
          close_at=find_close(line,start)
          if (close_at > 0) {
            if (mode=="sent") values="\"0x5200\", \"0x5203\""
            else values="\"0x5201\", \"0x5202\", \"0x5204\""
            if (has_element) addition=", " values
            else addition=values
            line=substr(line,1,close_at-1) addition substr(line,close_at)
            active=0
            if (mode=="sent") sent_done++
            else recv_done++
            mode=""
          } else {
            multiline=1
            buf[++buf_n]=line
            next
          }
        }
      }
      print line
    }
    END { if (sent_done != 1 || recv_done != 1 || active || pending) exit 2 }
  ' "${DIO_JSON}" > "${TMP}" || fail "Could not patch both dio_manager.json message arrays"

  for ITEM in \
    "MessagesSentByAccessory:0x5200" \
    "MessagesSentByAccessory:0x5203" \
    "MessagesReceivedFromDevice:0x5201" \
    "MessagesReceivedFromDevice:0x5202" \
    "MessagesReceivedFromDevice:0x5204"
  do
    KEY=${ITEM%%:*}
    VALUE=${ITEM#*:}
    set -- $(array_stats "${TMP}" "${KEY}" "${VALUE}")
    if [ "$1" -ne 1 ] || [ "$2" -ne 1 ]; then
      fail "Verification failed for ${KEY} ${VALUE}"
    fi
  done

  verify_dio_comments "${TMP}" || fail "CarPlay RGI message definition comment verification failed"

  chmod 644 "${TMP}" || fail "Could not chmod patched dio_manager.json"
  mv "${TMP}" "${DIO_JSON}" || fail "Could not install patched dio_manager.json"
}

patch_missing_dio_comments() {
  if verify_dio_comments "${DIO_JSON}"; then
    log "dio_manager.json already contains all five CarPlay RGI message definitions. Skipping..."
    return
  fi

  log "Adding missing CarPlay RGI message definitions to dio_manager.json"
  TMP="${DIO_JSON}.carplay-rgi.tmp"
  C5200=$(dio_comment_count "${DIO_JSON}" "0x5200/* StartRouteGuidanceUpdates */")
  C5203=$(dio_comment_count "${DIO_JSON}" "0x5203/* StopRouteGuidanceUpdates */")
  C5201=$(dio_comment_count "${DIO_JSON}" "0x5201/* RouteGuidanceUpdate */")
  C5202=$(dio_comment_count "${DIO_JSON}" "0x5202/* RouteGuidanceManeuverUpdate */")
  C5204=$(dio_comment_count "${DIO_JSON}" "0x5204/* RouteGuidanceLaneGuidanceInformation */")

  awk -v c5200="${C5200}" -v c5203="${C5203}" -v c5201="${C5201}" -v c5202="${C5202}" -v c5204="${C5204}" '
    function leading_ws(s) { match(s,/^[ \t]*/); return substr(s,1,RLENGTH) }
    {
      line=$0
      if (line !~ /^[ \t]*#/) {
        sent_pos=index(line,"\"MessagesSentByAccessory\"")
        recv_pos=index(line,"\"MessagesReceivedFromDevice\"")
        if (sent_pos > 0 && substr(line,sent_pos+length("\"MessagesSentByAccessory\"")) ~ /^[ \t]*:/) {
          indent=leading_ws(line)
          if (c5200==0) print indent "# , 0x5200/* StartRouteGuidanceUpdates */"
          if (c5203==0) print indent "# , 0x5203/* StopRouteGuidanceUpdates */"
          sent++
        } else if (recv_pos > 0 && substr(line,recv_pos+length("\"MessagesReceivedFromDevice\"")) ~ /^[ \t]*:/) {
          indent=leading_ws(line)
          if (c5201==0) print indent "# 0x5201/* RouteGuidanceUpdate */"
          if (c5202==0) print indent "# 0x5202/* RouteGuidanceManeuverUpdate */"
          if (c5204==0) print indent "# 0x5204/* RouteGuidanceLaneGuidanceInformation */"
          recv++
        }
      }
      print line
    }
    END { if (sent != 1 || recv != 1) exit 2 }
  ' "${DIO_JSON}" > "${TMP}" || fail "Could not add CarPlay RGI message definitions"

  verify_dio_comments "${TMP}" || fail "CarPlay RGI message definition comment verification failed"
  chmod 644 "${TMP}" || fail "Could not chmod patched dio_manager.json"
  mv "${TMP}" "${DIO_JSON}" || fail "Could not install patched dio_manager.json"
}

copy_component() {
  SOURCE="$1"
  TARGET="$2"
  MODE="$3"
  TMP="${TARGET}.carplay-rgi.tmp"

  cp -v "${SOURCE}" "${TMP}" || fail "Could not copy $(basename "${SOURCE}")"
  chmod "${MODE}" "${TMP}" || fail "Could not chmod $(basename "${TARGET}")"
  mv "${TMP}" "${TARGET}" || fail "Could not install $(basename "${TARGET}")"
}

save_modified_copy() {
  SOURCE="$1"
  TARGET="$2"
  TMP="${TARGET}.carplay-rgi.tmp"

  cp -v "${SOURCE}" "${TMP}" || fail "Could not stage $(basename "${TARGET}")"
  mv "${TMP}" "${TARGET}" || fail "Could not save $(basename "${TARGET}")"
}

verify_installation() {
  log "Verifying installed files and production configuration"

  require_file "${HOOK_TARGET}/libcarplay_hook.so"
  require_file "${HOOK_TARGET}/maneuver_render"
  require_file "${HOOK_TARGET}/flag_atlas.rgba"
  require_file "${JAR_TARGET}/carplay_hook.jar"

  set -- $(carplay_env_stats "${SMARTPHONE_JSON}")
  if [ "$1" -ne 1 ] || [ "$2" -ne 1 ] || [ "$3" -ne 1 ] || [ "$4" -ne 1 ] || [ "$(preload_count "${SMARTPHONE_JSON}")" -ne 1 ]; then
    fail "LD_PRELOAD is not present exactly once in carplay.envs"
  fi

  for ITEM in \
    "MessagesSentByAccessory:0x5200" \
    "MessagesSentByAccessory:0x5203" \
    "MessagesReceivedFromDevice:0x5201" \
    "MessagesReceivedFromDevice:0x5202" \
    "MessagesReceivedFromDevice:0x5204"
  do
    KEY=${ITEM%%:*}
    VALUE=${ITEM#*:}
    set -- $(array_stats "${DIO_JSON}" "${KEY}" "${VALUE}")
    if [ "$1" -ne 1 ] || [ "$2" -ne 1 ]; then
      fail "${VALUE} is not present exactly once in ${KEY}"
    fi
  done

  verify_dio_comments "${DIO_JSON}" || fail "CarPlay RGI message definitions are missing or duplicated"

  log "Configuration verification passed"
  grep -n "${PRELOAD_VALUE}" "${SMARTPHONE_JSON}"
  grep -n "0x520" "${DIO_JSON}"
}

trap 'fail "Installation interrupted by signal"' 1 2 15

log "===== CarPlay RGI installation started ====="
date
log "Firmware: ${VERSION}"
log "FAZIT: ${FAZIT}"
log "Source: ${APP_SOURCE}"
log "Backup: ${BACKUPFOLDER}"

recover_stale_transaction

require_file "${APP_SOURCE}/libcarplay_hook.so"
require_file "${APP_SOURCE}/maneuver_render"
require_file "${APP_SOURCE}/flag_atlas.rgba"
require_file "${APP_SOURCE}/carplay_hook.jar"
require_file "${SMARTPHONE_JSON}"
require_file "${DIO_JSON}"
preflight_configuration

backup_file "${SMARTPHONE_JSON}"
backup_file "${DIO_JSON}"
validate_original_backups
begin_transaction

log "Mounting /mnt/app and /mnt/system read-write"
mount -uw /mnt/app || fail "Could not mount /mnt/app read-write"
mount -uw /mnt/system || fail "Could not mount /mnt/system read-write"

mkdir -p "${HOOK_TARGET}" || fail "Could not create ${HOOK_TARGET}"
mkdir -p "${JAR_TARGET}" || fail "Could not create ${JAR_TARGET}"
chmod 755 "${HOOK_TARGET}" || fail "Could not set permissions on ${HOOK_TARGET}"

log "Copying CarPlay RGI files"
copy_component "${APP_SOURCE}/libcarplay_hook.so" "${HOOK_TARGET}/libcarplay_hook.so" 755
copy_component "${APP_SOURCE}/maneuver_render" "${HOOK_TARGET}/maneuver_render" 755
copy_component "${APP_SOURCE}/flag_atlas.rgba" "${HOOK_TARGET}/flag_atlas.rgba" 644
copy_component "${APP_SOURCE}/carplay_hook.jar" "${JAR_TARGET}/carplay_hook.jar" 644

patch_smartphone_integrator
if [ "${INSTALL_MODE}" = "first" ]; then
  patch_dio_manager
else
  log "dio_manager.json already contains all five CarPlay RGI message IDs."
  patch_missing_dio_comments
fi

verify_installation

log "Saving modified production configuration copies"
save_modified_copy "${SMARTPHONE_JSON}" "${BACKUPFOLDER}/smartphone_integrator_new.json"
save_modified_copy "${DIO_JSON}" "${BACKUPFOLDER}/dio_manager_new.json"

sync || fail "sync failed"
sleep 1
remount_read_only || fail "Could not remount /mnt/app and /mnt/system read-only"
touch "${TXN_DIR}/committed" || fail "Could not commit transaction state"

TXN_ACTIVE=0
rm -f "${TXN_DIR}/active" 2>/dev/null || true
rm -rf "${TXN_DIR}" 2>/dev/null || log "WARNING: Could not remove completed transaction snapshot ${TXN_DIR}"
trap - 1 2 15

log "CarPlay Route Guidance Interface installed successfully (${INSTALL_MODE} mode)."
log "Original and modified JSON files are stored at Backup/${VERSION}/CarPlayRGI"
log "Installation log: Backup/${VERSION}/CarPlayRGI/install_carplay_rgi.log"
log "Please wait at least 30 seconds, then reboot the headunit."
log "===== CarPlay RGI installation finished ====="

exit 0
