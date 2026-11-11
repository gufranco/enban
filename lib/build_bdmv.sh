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
  if ! disk_build_bdmv_root; then
    disk_error "--bdmv needs a BDMV folder at the root of the disc."
    return 1
  fi
  disk_build_alone_fields --bdmv
}

disk_build_alone_fields() {
  for disk_xc_pair in "--fs:${DISK_BUILD_FS#iso9660,joliet,udf}" "--dvd-video:${DISK_BUILD_DVD#n}" "--boot:${DISK_BUILD_BOOT}" "--publisher:${DISK_BUILD_PUBLISHER}" "--preparer:${DISK_BUILD_PREPARER}" "--application:${DISK_BUILD_APPLICATION}" "--system-id:${DISK_BUILD_SYSTEM}" "--volume-set:${DISK_BUILD_VOLSET}" "--date:${DISK_BUILD_DATE}" "--iso-level:${DISK_BUILD_LEVEL}"; do
    [ -z "${disk_xc_pair#*:}" ] && continue
    disk_error "$1 writes UDF ${DISK_BUILD_UDF_REV} alone, which holds a label and nothing more, so leave out ${disk_xc_pair%%:*}."
    return 1
  done
}

disk_build_bdmv() {
  disk_udf_write "$1"
}
