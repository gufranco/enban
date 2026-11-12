#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_checksum_check() {
  if [ -n "${DISK_CHECKSUM_IMAGE}" ]; then
    [ -f "${DISK_CHECKSUM_IMAGE}" ] && return 0
    disk_error "no image at ${DISK_CHECKSUM_IMAGE}."
    return 1
  fi
  disk_drive_read "${DISK_DRIVE}" checksum || return 1
  [ "${DISK_DRIVE_READABLE}" -gt 0 ] && return 0
  disk_error "stopped: the disc in ${DISK_DRIVE} holds no data to check."
  return 1
}

disk_checksum_digest() {
  disk_cd_os="$(disk_os)"
  case "${disk_cd_os}:$1" in
  Darwin:md5) md5 ;;
  Darwin:sha1) shasum -a 1 ;;
  Darwin:sha256) shasum -a 256 ;;
  *) "$1sum" ;;
  esac | awk '{ print $1 }'
}

disk_checksum_source() {
  if [ -n "${DISK_CHECKSUM_IMAGE}" ]; then
    cat "${DISK_CHECKSUM_IMAGE}"
    return
  fi
  disk_drive_dd bs=2048 count="${DISK_DRIVE_READABLE}" 2>/dev/null || : >"$1/failed"
}

disk_checksum_scan() {
  disk_cs_dir="$(mktemp -d "${TMPDIR:-/tmp}/enban-sum.XXXXXX")" || return 1
  mkfifo "${disk_cs_dir}/md5" "${disk_cs_dir}/sha1"
  disk_checksum_digest md5 <"${disk_cs_dir}/md5" >"${disk_cs_dir}/md5.out" &
  disk_checksum_digest sha1 <"${disk_cs_dir}/sha1" >"${disk_cs_dir}/sha1.out" &
  disk_checksum_source "${disk_cs_dir}" | tee "${disk_cs_dir}/md5" "${disk_cs_dir}/sha1" | disk_checksum_digest sha256 >"${disk_cs_dir}/sha256.out"
  wait
  DISK_CHECKSUM_MD5="$(cat "${disk_cs_dir}/md5.out")"
  DISK_CHECKSUM_SHA1="$(cat "${disk_cs_dir}/sha1.out")"
  DISK_CHECKSUM_SHA256="$(cat "${disk_cs_dir}/sha256.out")"
  disk_cs_failed=0
  [ ! -e "${disk_cs_dir}/failed" ] || disk_cs_failed=1
  rm -rf "${disk_cs_dir}"
  [ "${disk_cs_failed}" -eq 0 ] && return 0
  disk_error "unable to read the disc in ${DISK_DRIVE}."
  return 1
}

disk_checksum_done() {
  printf 'MD5      %s\nSHA-1    %s\nSHA-256  %s\n' "${DISK_CHECKSUM_MD5}" "${DISK_CHECKSUM_SHA1}" "${DISK_CHECKSUM_SHA256}"
  disk_ck_what="${DISK_CHECKSUM_IMAGE}"
  [ -n "${disk_ck_what}" ] || disk_ck_what="the disc in ${DISK_DRIVE}"
  disk_ck_line="Done. ${disk_ck_what} is checked."
  if disk_ui_out; then
    disk_ui_done "${disk_ck_line}"
    return 0
  fi
  printf '%s\n' "${disk_ck_line}"
}

disk_checksum_run() {
  disk_checksum_check || return 1
  disk_checksum_scan || return 1
  disk_checksum_done
}
