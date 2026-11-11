#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_write_image() {
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    disk_error "no image at $1."
    return 1
  fi
  disk_wi_bytes="$(wc -c <"$1" | tr -d '[:space:]')"
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
  disk_wc_name="${DISK_DRIVE##*/}"
  printf 'Type %s to write, or anything else to stop: ' "${disk_wc_name}" >&2
  disk_wc_answer=""
  IFS= read -r disk_wc_answer || disk_wc_answer=""
  [ "${disk_wc_answer}" = "${disk_wc_name}" ] && return 0
  disk_error "stopped: nothing was written."
  return 1
}

disk_write_burn() {
  disk_wb_log="$(mktemp "${TMPDIR:-/tmp}/enban-write.XXXXXX")" || return 1
  set -- -as cdrecord -v "dev=${DISK_DRIVE}" -dao
  [ -z "${DISK_WRITE_SPEED}" ] || set -- "$@" "speed=${DISK_WRITE_SPEED}"
  disk_wb_status=0
  xorriso "$@" "${DISK_WRITE_IMAGE}" >"${disk_wb_log}" 2>&1 || disk_wb_status="$?"
  disk_wb_reason="$(sed -n 's/^xorriso : FAILURE : //p' "${disk_wb_log}" | sed -n '1p')"
  rm -f "${disk_wb_log}"
  [ "${disk_wb_status}" -eq 0 ] && return 0
  disk_error "the write to ${DISK_DRIVE} failed: ${disk_wb_reason:-xorriso exited with ${disk_wb_status}.}"
  return 1
}

disk_write_verify() {
  disk_wv_source="${DISK_DRIVE#stdio:}"
  if dd if="${disk_wv_source}" bs=2048 count="${DISK_WRITE_SECTORS}" 2>/dev/null | cmp -s - "${DISK_WRITE_IMAGE}"; then
    return 0
  fi
  disk_error "the disc in ${DISK_DRIVE} does not match ${DISK_WRITE_IMAGE}."
  return 1
}

disk_write_eject() {
  xorriso -outdev "${DISK_DRIVE}" -eject all >/dev/null 2>&1 && return 0
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
  disk_write_go
}

disk_write_check() {
  disk_write_image "${DISK_WRITE_IMAGE}" || return 1
  disk_drive_read "${DISK_DRIVE}" write || return 1
  disk_write_fits "${DISK_WRITE_IMAGE}"
}

disk_write_go() {
  disk_write_burn || return 1
  if [ "${DISK_WRITE_VERIFY}" = y ]; then
    disk_write_verify || return 1
  fi
  if [ "${DISK_WRITE_EJECT}" = y ]; then
    disk_write_eject
  fi
  disk_write_done
}
