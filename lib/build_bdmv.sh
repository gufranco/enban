#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_build_bdmv_root() {
  if [ -z "${DISK_BUILD_LAYOUT}" ]; then
    [ -d "${DISK_BUILD_SOURCE%/}/BDMV" ]
    return
  fi
  disk_xa_dir="$(printf '%s\n' "${DISK_BUILD_LAYOUT}" | awk -F "${DISK_TAB}" '$1 == "BDMV" { print $2; exit }')"
  [ -n "${disk_xa_dir}" ] && [ -d "${disk_xa_dir}" ]
}

disk_build_bdmv_check() {
  [ "${DISK_BUILD_BDMV}" = y ] || return 0
  disk_xb_os="$(disk_os)"
  if [ "${disk_xb_os}" != Darwin ]; then
    disk_error "--bdmv needs UDF 2.50, which no Linux tool writes into an image. build it on macOS."
    return 1
  fi
  if ! disk_build_bdmv_root; then
    disk_error "--bdmv needs a BDMV folder at the root of the disc."
    return 1
  fi
  disk_build_bdmv_alone
}

disk_build_bdmv_alone() {
  for disk_xc_pair in "--fs:${DISK_BUILD_FS#iso9660,joliet,udf}" "--dvd-video:${DISK_BUILD_DVD#n}" "--boot:${DISK_BUILD_BOOT}" "--publisher:${DISK_BUILD_PUBLISHER}" "--preparer:${DISK_BUILD_PREPARER}" "--application:${DISK_BUILD_APPLICATION}" "--system-id:${DISK_BUILD_SYSTEM}" "--volume-set:${DISK_BUILD_VOLSET}" "--date:${DISK_BUILD_DATE}" "--iso-level:${DISK_BUILD_LEVEL}"; do
    [ -z "${disk_xc_pair#*:}" ] && continue
    disk_error "--bdmv writes UDF 2.50 alone, which holds a label and nothing more, so leave out ${disk_xc_pair%%:*}."
    return 1
  done
}

disk_build_bdmv_kib() {
  if [ -z "${DISK_BUILD_LAYOUT}" ]; then
    disk_xh_used="$(du -sk "${DISK_BUILD_SOURCE}" | cut -f 1)"
  else
    disk_xh_used="$(printf '%s\n' "${DISK_BUILD_LAYOUT}" | cut -f 2 | disk_build_bdmv_sum)"
  fi
  disk_xh_kib=$((disk_xh_used * 105 / 100 + 8192))
  printf '%s\n' $((disk_xh_kib + disk_xh_kib % 2))
}

disk_build_bdmv_sum() {
  while IFS= read -r disk_xe_source; do
    du -sk "${disk_xe_source}" | cut -f 1
  done | awk '{ total += $1 } END { print total + 0 }'
}

disk_build_bdmv_blank() {
  disk_xf_kib="$(disk_build_bdmv_kib)"
  dd if=/dev/zero of="$1" bs=1024 count=0 seek="${disk_xf_kib}" 2>/dev/null || return 1
  disk_xf_dev="$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount "$1" 2>/dev/null | awk 'NR == 1 { print $1 }')"
  [ -n "${disk_xf_dev}" ] || return 1
  disk_xf_status=0
  newfs_udf -r 2.50 -b 2048 -v "${DISK_BUILD_VOLUME}" "${disk_xf_dev}" >/dev/null 2>&1 || disk_xf_status=1
  disk_build_bdmv_detach "${disk_xf_dev}" || disk_xf_status=1
  return "${disk_xf_status}"
}

disk_build_bdmv_fill() {
  mkdir "$1/.fseventsd" || return 1
  : >"$1/.fseventsd/no_log" || return 1
  if [ -z "${DISK_BUILD_LAYOUT}" ]; then
    cp -R "${DISK_BUILD_SOURCE%/}/." "$1/" || return 1
  else
    printf '%s\n' "${DISK_BUILD_LAYOUT}" | cut -f 1,2 | disk_build_copy "$1" || return 1
  fi
  rm -rf "$1/.fseventsd"
}

disk_build_bdmv() {
  disk_build_bdmv_blank "$1" || return 1
  mkdir "$1.mnt" || return 1
  disk_xg_status=0
  hdiutil attach -imagekey diskimage-class=CRawDiskImage -nobrowse -mountpoint "$1.mnt" "$1" >/dev/null 2>&1 || disk_xg_status=1
  if [ "${disk_xg_status}" -eq 0 ]; then
    disk_build_bdmv_fill "$1.mnt" || disk_xg_status=1
    disk_build_bdmv_detach "$1.mnt" || disk_xg_status=1
  fi
  rmdir "$1.mnt"
  return "${disk_xg_status}"
}

disk_build_bdmv_detach() {
  disk_xi_try=0
  while [ "${disk_xi_try}" -lt "${DISK_BUILD_DETACH_TRIES}" ]; do
    hdiutil detach "$1" >/dev/null 2>&1 && return 0
    disk_xi_try=$((disk_xi_try + 1))
    sleep 1
  done
  hdiutil detach -force "$1" >/dev/null 2>&1
}
