#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_write_image() {
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    disk_error "no image at $1."
    return 1
  fi
  disk_wi_bytes="$(disk_file_bytes "$1")"
  if [ "${disk_wi_bytes}" -eq 0 ] || [ $((disk_wi_bytes % 2048)) -ne 0 ]; then
    disk_error "$1 is not a disc image: its size is not a whole number of 2048-byte sectors."
    return 1
  fi
  DISK_WRITE_SECTORS=$((disk_wi_bytes / 2048))
}

disk_write_fits() {
  if [ "${DISK_DRIVE_STATUS}" != blank ]; then
    disk_error "stopped: the disc in ${DISK_DRIVE} is not blank."
    return 1
  fi
  if [ "${DISK_WRITE_SECTORS}" -gt "${DISK_DRIVE_FREE}" ]; then
    disk_error "stopped: $1 needs ${DISK_WRITE_SECTORS} sectors and the disc in ${DISK_DRIVE} has ${DISK_DRIVE_FREE} free."
    return 1
  fi
}

disk_write_confirm() {
  disk_wc_name="$(disk_drive_word "${DISK_DRIVE}")"
  printf 'Type %s to write, or anything else to stop: ' "${disk_wc_name}" >&2
  disk_wc_answer=""
  IFS= read -r disk_wc_answer || disk_wc_answer=""
  [ "${disk_wc_answer}" = "${disk_wc_name}" ] && return 0
  disk_error "stopped: nothing was written."
  return 1
}

disk_write_burn() {
  disk_wb_log="$(mktemp "${TMPDIR:-/tmp}/enban-write.XXXXXX")" || return 1
  set -- -v "dev=${DISK_DRIVE}" "-${DISK_WRITE_MODE}"
  [ "${DISK_WRITE_FINALIZE}" = y ] || set -- "$@" -multi
  [ -z "${DISK_WRITE_SPEED}" ] || set -- "$@" "speed=${DISK_WRITE_SPEED}"
  [ "${DISK_WRITE_TEST}" = n ] || set -- "$@" -dummy
  disk_wb_status=0
  disk_drive_cdrecord "$@" "${DISK_WRITE_IMAGE}" >"${disk_wb_log}" 2>&1 || disk_wb_status="$?"
  disk_wb_reason="$(disk_drive_reason "${disk_wb_log}")"
  rm -f "${disk_wb_log}"
  [ "${disk_wb_status}" -eq 0 ] && return 0
  disk_wb_tool="$(disk_drive_burner)"
  disk_error "the write to ${DISK_DRIVE} failed: ${disk_wb_reason:-${disk_wb_tool} exited with ${disk_wb_status}.}"
  return 1
}

disk_write_verify() {
  if disk_drive_dd bs=2048 count="${DISK_WRITE_SECTORS}" 2>/dev/null | cmp -s - "${DISK_WRITE_IMAGE}"; then
    return 0
  fi
  disk_error "the disc in ${DISK_DRIVE} does not match ${DISK_WRITE_IMAGE}."
  return 1
}

disk_write_eject() {
  disk_drive_eject && return 0
  DISK_WRITE_EJECT=n
  disk_warning "the disc is written, but ${DISK_DRIVE} did not open its tray."
}

disk_write_done() {
  disk_wd_text="written"
  case "${DISK_WRITE_VERIFY}:${DISK_WRITE_EJECT}" in
  y:y) disk_wd_text="written, verified and ejected" ;;
  y:n) disk_wd_text="written and verified" ;;
  n:y) disk_wd_text="written and ejected" ;;
  *) disk_wd_text="written" ;;
  esac
  disk_wd_line="Done. ${DISK_DRIVE} is ${disk_wd_text}."
  if disk_ui_out; then
    disk_ui_done "${disk_wd_line}"
    return 0
  fi
  printf '%s\n' "${disk_wd_line}"
}

disk_write_run() {
  disk_write_check || return 1
  disk_write_confirm || return 1
  disk_write_copies
}

disk_write_mode_ok() {
  case "${DISK_WRITE_MODE}" in
  dao | tao) return 0 ;;
  sao) DISK_WRITE_MODE=dao ;;
  *)
    disk_error "--mode takes dao or tao, got: ${DISK_WRITE_MODE}"
    return 1
    ;;
  esac
}

disk_write_copies_ok() {
  case "${DISK_WRITE_COPIES}" in
  '' | *[!0-9]* | 0)
    disk_error "--copies must be a whole number from 1 to 100, got: ${DISK_WRITE_COPIES}"
    return 1
    ;;
  *) : ;;
  esac
  if [ "${DISK_WRITE_COPIES}" -gt 100 ]; then
    disk_error "--copies must be a whole number from 1 to 100, got: ${DISK_WRITE_COPIES}"
    return 1
  fi
  [ "${DISK_WRITE_COPIES}" -eq 1 ] || [ "${DISK_WRITE_EJECT}" = y ] && return 0
  disk_error "--copies opens the tray between copies, so it cannot run with --no-eject."
  return 1
}

disk_write_next() {
  disk_say "Copy $1 of ${DISK_WRITE_COPIES}: waiting for a blank disc in ${DISK_DRIVE}."
  if ! disk_queue_wait "${DISK_DRIVE}"; then
    disk_error "no blank disc arrived in ${DISK_QUEUE_WAIT} seconds, so copy $1 of ${DISK_WRITE_COPIES} was not written."
    return 1
  fi
  disk_write_fits "${DISK_WRITE_IMAGE}"
}

disk_write_copies() {
  disk_wy_copy=1
  while [ "${disk_wy_copy}" -le "${DISK_WRITE_COPIES}" ]; do
    [ "${disk_wy_copy}" -eq 1 ] || disk_write_next "${disk_wy_copy}" || return 1
    disk_write_go || return 1
    disk_wy_copy=$((disk_wy_copy + 1))
  done
  disk_write_delete
}

disk_write_delete() {
  [ "${DISK_WRITE_DELETE}" = y ] || return 0
  disk_wd_image="${DISK_WRITE_SOURCE:-${DISK_WRITE_IMAGE}}"
  if [ "${DISK_WRITE_TEST}" = y ]; then
    disk_say "Kept ${disk_wd_image}, since a test write burns nothing."
    return 0
  fi
  if rm -f "${disk_wd_image}"; then
    disk_say "Deleted ${disk_wd_image}, as asked."
    return 0
  fi
  disk_error "every copy is written, but ${disk_wd_image} could not be deleted."
  return 1
}

disk_write_check() {
  disk_write_image "${DISK_WRITE_IMAGE}" || return 1
  disk_drive_read "${DISK_DRIVE}" write || return 1
  disk_write_fits "${DISK_WRITE_IMAGE}" || return 1
  disk_write_opc_ready || return 1
  disk_speeds_recall
}

disk_write_opc_ready() {
  [ "${DISK_WRITE_OPC}" = y ] || return 0
  command -v sg_raw >/dev/null 2>&1 && return 0
  disk_error "--opc needs sg_raw from sg3-utils to calibrate the laser. install it and try again."
  return 1
}

disk_write_opc() {
  [ "${DISK_WRITE_OPC}" = y ] || return 0
  disk_say "Calibrating the laser power of ${DISK_DRIVE}."
  disk_wq_device="$(disk_raw_device)"
  disk_raw_send "${disk_wq_device}" 54 01 00 00 00 00 00 00 00 00
}

disk_write_tested() {
  disk_raw_done "Done. the test write to ${DISK_DRIVE} ran to the end, and nothing was written."
}

disk_write_go() {
  disk_write_opc || return 1
  disk_write_burn || return 1
  if [ "${DISK_WRITE_TEST}" = y ]; then
    disk_write_tested
    return 0
  fi
  disk_speeds_keep
  if [ "${DISK_WRITE_VERIFY}" = y ]; then
    disk_write_verify || return 1
  fi
  if [ "${DISK_WRITE_EJECT}" = y ]; then
    disk_write_eject
  fi
  disk_write_done
}
