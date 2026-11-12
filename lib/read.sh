#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_read_check() {
  disk_drive_read "${DISK_DRIVE}" read || return 1
  case "${DISK_DRIVE_STATUS}" in
  appendable | closed) : ;;
  *)
    disk_error "stopped: the disc in ${DISK_DRIVE} holds no data to read."
    return 1
    ;;
  esac
  if [ -e "${DISK_READ_OUT}" ]; then
    disk_error "stopped: ${DISK_READ_OUT} already exists."
    return 1
  fi
}

disk_read_retries_ok() {
  case "${DISK_READ_RETRIES}" in
  [0-9] | [1-9][0-9]) return 0 ;;
  *)
    disk_error "--retries must be a whole number from 0 to 99, got: ${DISK_READ_RETRIES}"
    return 1
    ;;
  esac
}

disk_read_speed() {
  [ -n "${DISK_SPEED_OPTION}" ] || return 0
  DISK_SPEED_WANTED="${DISK_WRITE_SPEED}"
  disk_speed_run
}

disk_read_once() {
  rm -f "${DISK_READ_OUT}"
  dd if="${DISK_DRIVE#stdio:}" of="${DISK_READ_OUT}" bs=2048 count="${DISK_DRIVE_READABLE}" 2>/dev/null
}

disk_read_copy() {
  disk_ry_try=0
  while ! disk_read_once; do
    disk_ry_try=$((disk_ry_try + 1))
    if [ "${disk_ry_try}" -gt "${DISK_READ_RETRIES}" ]; then
      [ "${DISK_READ_IGNORE}" = n ] || {
        disk_read_salvage
        return
      }
      disk_read_drop
      disk_error "unable to read ${DISK_DRIVE} into ${DISK_READ_OUT}."
      return 1
    fi
    disk_say "Reading ${DISK_DRIVE} again, try $((disk_ry_try + 1)) of $((DISK_READ_RETRIES + 1))."
  done
}

disk_read_drop() {
  [ -e "${DISK_READ_OUT}" ] || return 0
  if [ "${DISK_EVENT_CLEAN}" = n ]; then
    disk_say "The half-read ${DISK_READ_OUT} is kept."
    return 0
  fi
  rm -f "${DISK_READ_OUT}"
  [ "${DISK_READ_CCD}" = n ] || rm -f "${DISK_READ_OUT%.*}.sub"
  disk_say "Deleted the half-read ${DISK_READ_OUT}."
}

disk_read_salvage() {
  disk_rz_errors="$(mktemp "${TMPDIR:-/tmp}/enban-salvage.XXXXXX")" || return 1
  dd if="${DISK_DRIVE#stdio:}" of="${DISK_READ_OUT}" bs=2048 count="${DISK_DRIVE_READABLE}" conv=noerror,sync 2>"${disk_rz_errors}"
  DISK_READ_BAD="$(grep -c 'error reading' "${disk_rz_errors}")"
  rm -f "${disk_rz_errors}"
  disk_warning "${DISK_READ_BAD} sectors of ${DISK_DRIVE} could not be read and are zeros in ${DISK_READ_OUT}."
}

disk_read_cue() {
  [ "${DISK_READ_CUE}" = y ] || return 0
  disk_rq_name="${DISK_READ_OUT##*/}"
  printf 'FILE "%s" BINARY\n  TRACK 01 MODE1/2048\n    INDEX 01 00:00:00\n' "${disk_rq_name}" >"${DISK_READ_OUT%.*}.cue"
}

disk_read_verify() {
  disk_rv_source="${DISK_DRIVE#stdio:}"
  if dd if="${disk_rv_source}" bs=2048 count="${DISK_DRIVE_READABLE}" 2>/dev/null | cmp -s - "${DISK_READ_OUT}"; then
    return 0
  fi
  disk_error "the copy in ${DISK_READ_OUT} does not match the disc in ${DISK_DRIVE}."
  return 1
}

disk_read_done() {
  disk_rd_digest="$(disk_checksum_digest sha256 <"${DISK_READ_OUT}")"
  disk_rd_md5="$(disk_checksum_digest md5 <"${DISK_READ_OUT}")"
  disk_rd_text="read into ${DISK_READ_OUT}"
  [ "${DISK_READ_VERIFY}" != y ] || [ "${DISK_READ_BAD}" -gt 0 ] || disk_rd_text="${disk_rd_text} and verified"
  disk_rd_line="Done. ${DISK_DRIVE} is ${disk_rd_text}."
  printf 'Sectors  %s\nMD5      %s\nSHA-256  %s\n' "${DISK_DRIVE_READABLE}" "${disk_rd_md5}" "${disk_rd_digest}"
  [ "${DISK_READ_CCD}" = n ] || printf 'CloneCD  %s.ccd and %s.sub\n' "${DISK_READ_OUT%.*}" "${DISK_READ_OUT%.*}"
  if disk_ui_out; then
    disk_ui_done "${disk_rd_line}"
    return 0
  fi
  printf '%s\n' "${disk_rd_line}"
}

disk_read_run() {
  disk_read_check || return 1
  disk_read_ccd_ready || return 1
  disk_read_speed || return 1
  disk_read_image || return 1
  disk_read_cue
  [ "${DISK_READ_CCD}" = n ] || disk_read_ccd_layout || return 1
  if [ "${DISK_READ_VERIFY}" = y ] && [ "${DISK_READ_BAD}" -eq 0 ]; then
    disk_read_compare || return 1
  fi
  disk_read_done
}

disk_read_image() {
  if [ "${DISK_READ_CCD}" = y ]; then
    disk_read_ccd_copy
    return
  fi
  disk_job_note "${DISK_READ_OUT}"
  disk_read_copy
}

disk_read_compare() {
  if [ "${DISK_READ_CCD}" = y ]; then
    disk_read_ccd_verify
    return
  fi
  disk_read_verify
}
