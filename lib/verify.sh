#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_verify_check() {
  disk_drive_read "${DISK_DRIVE}" verify || return 1
  case "${DISK_DRIVE_STATUS}" in
  appendable | closed) : ;;
  *)
    disk_error "stopped: the disc in ${DISK_DRIVE} holds no data to verify."
    return 1
    ;;
  esac
  DISK_VERIFY_SECTORS="${DISK_DRIVE_READABLE}"
  [ -n "${DISK_VERIFY_IMAGE}" ] || return 0
  disk_write_image "${DISK_VERIFY_IMAGE}" || return 1
  if [ "${DISK_WRITE_SECTORS}" -gt "${DISK_DRIVE_READABLE}" ]; then
    disk_error "stopped: ${DISK_VERIFY_IMAGE} has ${DISK_WRITE_SECTORS} sectors and the disc in ${DISK_DRIVE} holds ${DISK_DRIVE_READABLE}."
    return 1
  fi
  DISK_VERIFY_SECTORS="${DISK_WRITE_SECTORS}"
}

disk_verify_stream() {
  dd if="${DISK_DRIVE#stdio:}" bs=2048 count="${DISK_VERIFY_SECTORS}" 2>"$1"
}

disk_verify_compare() {
  if [ -z "${DISK_VERIFY_IMAGE}" ]; then
    cat >/dev/null
    printf '0 -\n'
    return 0
  fi
  cmp -l - "${DISK_VERIFY_IMAGE}" 2>/dev/null | awk '
    BEGIN { last = -1; n = 0; first = "-" }
    {
      s = int(($1 - 1) / 2048)
      if (s == last) next
      last = s
      if (n == 0) first = s
      n++
    }
    END { print n, first }'
}

disk_verify_scan() {
  disk_vs_dir="$(mktemp -d "${TMPDIR:-/tmp}/enban-verify.XXXXXX")" || return 1
  disk_vs_result="$(disk_verify_stream "${disk_vs_dir}/dd" | disk_verify_compare)"
  DISK_VERIFY_READ="$(sed -n 's/^\([0-9][0-9]*\)+[0-9][0-9]* records in$/\1/p' "${disk_vs_dir}/dd")"
  rm -rf "${disk_vs_dir}"
  DISK_VERIFY_MISS="${disk_vs_result% *}"
  DISK_VERIFY_FIRST="${disk_vs_result#* }"
  DISK_VERIFY_READ="${DISK_VERIFY_READ:-0}"
}

disk_verify_report() {
  disk_vr_lost=$((DISK_VERIFY_SECTORS - DISK_VERIFY_READ))
  printf 'Readable     %s of %s sectors\n' "${DISK_VERIFY_READ}" "${DISK_VERIFY_SECTORS}"
  printf 'Miscompares  %s\nUnreadable   %s\n' "${DISK_VERIFY_MISS}" "${disk_vr_lost}"
  if [ "${DISK_VERIFY_MISS}" -gt 0 ]; then
    disk_error "the disc in ${DISK_DRIVE} differs from ${DISK_VERIFY_IMAGE}, first at sector ${DISK_VERIFY_FIRST}."
    return 1
  fi
  if [ "${disk_vr_lost}" -gt 0 ]; then
    disk_error "${disk_vr_lost} sectors of the disc in ${DISK_DRIVE} could not be read, from sector ${DISK_VERIFY_READ}."
    return 1
  fi
  disk_verify_done
}

disk_verify_done() {
  disk_vd_line="Done. every sector of ${DISK_DRIVE} can be read."
  [ -z "${DISK_VERIFY_IMAGE}" ] || disk_vd_line="Done. ${DISK_DRIVE} matches ${DISK_VERIFY_IMAGE} byte for byte."
  if disk_ui_out; then
    disk_ui_done "${disk_vd_line}"
    return 0
  fi
  printf '%s\n' "${disk_vd_line}"
}

disk_verify_run() {
  disk_verify_check || return 1
  disk_verify_scan || return 1
  disk_verify_report
}
