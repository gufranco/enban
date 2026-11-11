#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_booktype_spec() {
  case "$1" in
  dvd-rom) printf -- '-dvd-rom-spec DVD-ROM\n' ;;
  dvd+r) printf -- '-dvd+r-spec DVD+R\n' ;;
  *) printf -- '-dvd+rw-spec DVD+RW\n' ;;
  esac
}

disk_booktype_ready() {
  disk_drive_read "${DISK_DRIVE}" booktype || return 1
  if ! command -v dvd+rw-booktype >/dev/null 2>&1; then
    disk_error "booktype needs dvd+rw-booktype from dvd+rw-tools. install it and try again."
    return 1
  fi
  disk_br_user="$(id -u)"
  if [ "${disk_br_user}" != 0 ]; then
    disk_error "the book type needs root. run the same command again with sudo."
    return 1
  fi
  case "${DISK_DRIVE_CODE}" in
  001a | 001b | 002a | 002b) return 0 ;;
  *) : ;;
  esac
  disk_br_name="$(disk_drive_short_profile)"
  disk_error "stopped: the book type applies to DVD+R and DVD+RW discs, and the disc in ${DISK_DRIVE} is a ${disk_br_name}."
  return 1
}

disk_booktype_run() {
  disk_booktype_ready || return 1
  disk_bt_device="$(disk_raw_device)"
  if [ -z "${DISK_BOOKTYPE}" ]; then
    dvd+rw-booktype -inq "${disk_bt_device}"
    return
  fi
  disk_raw_typed "change its book type" || return 1
  disk_booktype_go
}

disk_booktype_go() {
  disk_bt_device="$(disk_raw_device)"
  disk_bt_spec="$(disk_booktype_spec "${DISK_BOOKTYPE}")"
  disk_bt_errors="$(mktemp "${TMPDIR:-/tmp}/enban-book.XXXXXX")" || return 1
  disk_bt_status=0
  dvd+rw-booktype "${disk_bt_spec% *}" -media "${disk_bt_device}" >/dev/null 2>"${disk_bt_errors}" || disk_bt_status=1
  disk_bt_reason="$(sed -n '$p' "${disk_bt_errors}")"
  rm -f "${disk_bt_errors}"
  if [ "${disk_bt_status}" -ne 0 ]; then
    disk_error "the book type did not change: ${disk_bt_reason:-dvd+rw-booktype failed.}"
    return 1
  fi
  disk_raw_done "Done. the disc in ${DISK_DRIVE} reads as ${disk_bt_spec#* }."
}
