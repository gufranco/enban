#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_read_check() {
  disk_drive_read "${DISK_DRIVE}" read || return 1
  case "${DISK_DRIVE_STATUS}" in
  appendable | closed) ;;
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

disk_read_copy() {
  disk_rc_source="${DISK_DRIVE#stdio:}"
  if dd if="${disk_rc_source}" of="${DISK_READ_OUT}" bs=2048 count="${DISK_DRIVE_READABLE}" 2>/dev/null; then
    return 0
  fi
  disk_error "unable to read ${DISK_DRIVE} into ${DISK_READ_OUT}."
  return 1
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
  disk_rd_digest="$(sha256sum "${DISK_READ_OUT}")"
  disk_rd_text="read into ${DISK_READ_OUT}"
  [ "${DISK_WRITE_VERIFY}" != y ] || disk_rd_text="${disk_rd_text} and verified"
  disk_rd_line="Done. ${DISK_DRIVE} is ${disk_rd_text}."
  printf 'Sectors  %s\nSHA-256  %s\n' "${DISK_DRIVE_READABLE}" "${disk_rd_digest%% *}"
  if disk_ui_out; then
    disk_ui_done "${disk_rd_line}"
    return 0
  fi
  printf '%s\n' "${disk_rd_line}"
}

disk_read_run() {
  disk_read_check || return 1
  disk_read_copy || return 1
  if [ "${DISK_WRITE_VERIFY}" = y ]; then
    disk_read_verify || return 1
  fi
  disk_read_done
}
