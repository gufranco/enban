#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_erase_check() {
  disk_drive_read "${DISK_DRIVE}" erase || return 1
  if [ "${DISK_DRIVE_STATUS}" = blank ]; then
    disk_error "stopped: the disc in ${DISK_DRIVE} is already blank."
    return 1
  fi
  case "${DISK_DRIVE_CODE}" in
  000a | 0012 | 0013 | 0014 | 001a | 002a | 0043) return 0 ;;
  *)
    disk_ec_name="$(disk_drive_short_profile)"
    disk_error "stopped: the disc in ${DISK_DRIVE} is a ${disk_ec_name}, which cannot be erased."
    return 1
    ;;
  esac
}

disk_erase_confirm() {
  disk_eo_name="$(disk_drive_word "${DISK_DRIVE}")"
  printf 'Type %s to erase, or anything else to stop: ' "${disk_eo_name}" >&2
  disk_eo_answer=""
  IFS= read -r disk_eo_answer || disk_eo_answer=""
  [ "${disk_eo_answer}" = "${disk_eo_name}" ] && return 0
  disk_error "cancelled, nothing was touched."
  return 1
}

disk_erase_blank() {
  disk_eb_mode=fast
  [ "${DISK_ERASE_FULL}" = n ] || disk_eb_mode=all
  disk_eb_log="$(mktemp "${TMPDIR:-/tmp}/enban-erase.XXXXXX")" || return 1
  disk_eb_status=0
  disk_drive_blank "${disk_eb_mode}" >"${disk_eb_log}" 2>&1 || disk_eb_status="$?"
  disk_eb_reason="$(disk_drive_reason "${disk_eb_log}")"
  rm -f "${disk_eb_log}"
  [ "${disk_eb_status}" -eq 0 ] && return 0
  disk_eb_tool="$(disk_drive_burner)"
  disk_error "the erase of ${DISK_DRIVE} failed: ${disk_eb_reason:-${disk_eb_tool} exited with ${disk_eb_status}.}"
  return 1
}

disk_erase_done() {
  disk_ed_line="Done. ${DISK_DRIVE} is erased."
  [ "${DISK_ERASE_FULL}" = n ] || disk_ed_line="Done. ${DISK_DRIVE} is erased in full."
  if disk_ui_out; then
    disk_ui_done "${disk_ed_line}"
    return 0
  fi
  printf '%s\n' "${disk_ed_line}"
}

disk_erase_go() {
  disk_erase_blank || return 1
  disk_erase_done
}

disk_erase_run() {
  disk_erase_check || return 1
  disk_erase_confirm || return 1
  disk_erase_go
}
