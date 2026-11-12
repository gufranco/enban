#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_tray_run() {
  disk_raw_ready tray || return 1
  if disk_mac_drive "${DISK_DRIVE}"; then
    disk_mac_tray
    return
  fi
  disk_ty_device="$(disk_raw_device)"
  case "${DISK_TRAY_ACTION}" in
  load)
    disk_raw_send "${disk_ty_device}" 1b 00 00 00 03 00 || return 1
    disk_ty_line="Done. the tray of ${DISK_DRIVE} is closed and its disc loaded."
    ;;
  lock)
    disk_raw_send "${disk_ty_device}" 1e 00 00 00 01 00 || return 1
    disk_ty_line="Done. the tray of ${DISK_DRIVE} is locked until it is unlocked or the drive restarts."
    ;;
  *)
    disk_raw_send "${disk_ty_device}" 1e 00 00 00 00 00 || return 1
    disk_ty_line="Done. the tray of ${DISK_DRIVE} is unlocked."
    ;;
  esac
  disk_raw_done "${disk_ty_line}"
}

disk_rezero_run() {
  disk_raw_ready rezero || return 1
  if disk_mac_drive "${DISK_DRIVE}"; then
    disk_mac_cdrecord -load || return 1
  else
    disk_rz_device="$(disk_raw_device)"
    disk_raw_send "${disk_rz_device}" 01 00 00 00 00 00 || return 1
  fi
  disk_raw_done "Done. ${DISK_DRIVE} moved its head back to the start of the disc."
}

disk_sync_run() {
  disk_raw_ready sync || return 1
  if disk_mac_drive "${DISK_DRIVE}"; then
    disk_mac_cdrecord -abort || return 1
  else
    disk_sy_device="$(disk_raw_device)"
    disk_raw_send "${disk_sy_device}" 35 00 00 00 00 00 00 00 00 00 || return 1
  fi
  disk_raw_done "Done. ${DISK_DRIVE} wrote its cache to the disc."
}

disk_close_last_track() {
  disk_cl_file="$(mktemp "${TMPDIR:-/tmp}/enban-info.XXXXXX")" || return 1
  disk_cl_device="$(disk_raw_device)"
  if ! disk_raw_send -r 34 -o "${disk_cl_file}" "${disk_cl_device}" 51 00 00 00 00 00 00 00 22 00; then
    rm -f "${disk_cl_file}"
    return 1
  fi
  od -An -tu1 -v -N 12 "${disk_cl_file}" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) b[n++] = $i } END { print b[11] * 256 + b[6] }'
  rm -f "${disk_cl_file}"
}

disk_close_track() {
  disk_ct_track="$(disk_close_last_track)" || return 1
  disk_ct_bytes="$(printf '%02x %02x' $((disk_ct_track / 256)) $((disk_ct_track % 256)))"
  disk_ct_device="$(disk_raw_device)"
  # shellcheck disable=SC2086
  disk_raw_send "${disk_ct_device}" 5b 01 01 00 ${disk_ct_bytes} 00 00 00 00 || return 1
  disk_raw_done "Done. track ${disk_ct_track} on ${DISK_DRIVE} is closed."
}
