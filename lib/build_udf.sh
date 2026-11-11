#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_build_udf_version_check() {
  DISK_BUILD_ALONE="${DISK_BUILD_BDMV}"
  DISK_BUILD_UDF_REV=2.50
  [ -n "${DISK_BUILD_UDF_VERSION}" ] || return 0
  disk_build_udf_version_known || return 1
  disk_build_udf_version_fits || return 1
  DISK_BUILD_UDF_REV="${DISK_BUILD_UDF_VERSION}"
  disk_build_udf_version_tool
}

disk_build_udf_version_known() {
  case "${DISK_BUILD_UDF_VERSION}" in
  1.02 | 1.50 | 2.00 | 2.01 | 2.50 | 2.60) return 0 ;;
  *)
    disk_error "--udf-version takes 1.02, 1.50, 2.00, 2.01, 2.50 or 2.60, got: ${DISK_BUILD_UDF_VERSION}"
    return 1
    ;;
  esac
}

disk_build_udf_version_fits() {
  if [ "${DISK_BUILD_UDF}" = n ]; then
    disk_error "--udf-version needs udf in --fs."
    return 1
  fi
  if [ "${DISK_BUILD_DVD}" = y ] && [ "${DISK_BUILD_UDF_VERSION}" != 1.02 ]; then
    disk_error "--dvd-video uses UDF 1.02, the revision a DVD player reads."
    return 1
  fi
  [ "${DISK_BUILD_BDMV}" = n ] || [ "${DISK_BUILD_UDF_VERSION}" = 2.50 ] && return 0
  disk_error "--bdmv uses UDF 2.50, the revision a Blu-ray player reads."
  return 1
}

disk_build_udf_version_tool() {
  disk_ua_os="$(disk_os)"
  if [ "${disk_ua_os}" != Darwin ]; then
    [ "${DISK_BUILD_UDF_VERSION}" = 1.02 ] && return 0
    disk_error "--udf-version ${DISK_BUILD_UDF_VERSION} needs macOS, since genisoimage, which builds UDF on Linux, writes 1.02 only."
    return 1
  fi
  case "${DISK_BUILD_UDF_VERSION}" in
  1.02 | 1.50) return 0 ;;
  *) DISK_BUILD_ALONE=y ;;
  esac
  disk_build_alone_fields "--udf-version ${DISK_BUILD_UDF_VERSION}"
}
