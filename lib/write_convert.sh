#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_write_foreign() {
  case "$1" in
  *.[cC][cC][dD] | *.[cC][dD][iI] | *.[mM][dD][sS] | *.[mM][dD][fF] | *.[nN][rR][gG] | *.[iI][mM][gG] | *.[dD][iI] | *.[gG][iI] | *.[pP][dD][iI]) : ;;
  *) return 1 ;;
  esac
  [ -f "$1" ] || return 1
  ! disk_iso_is "$1"
}

disk_write_converted() {
  disk_wk_dir="$(mktemp -d "${TMPDIR:-/tmp}/enban-wconv.XXXXXX")" || return 1
  DISK_CONVERT_IN="${DISK_WRITE_IMAGE}"
  DISK_CONVERT_OUT="${disk_wk_dir}/image.iso"
  disk_say "Converting ${DISK_WRITE_IMAGE} to an ISO image before the burn."
  disk_wk_status=0
  if disk_convert_run >/dev/null; then
    DISK_WRITE_SOURCE="${DISK_WRITE_IMAGE}"
    DISK_WRITE_IMAGE="${DISK_CONVERT_OUT}"
    disk_write_run || disk_wk_status=1
  else
    disk_wk_status=1
  fi
  rm -rf "${disk_wk_dir}"
  return "${disk_wk_status}"
}
