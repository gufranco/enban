#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_build_ids_fits() {
  [ "${#2}" -le "$3" ] && return 0
  disk_error "$1 takes up to $3 characters, got ${#2}."
  return 1
}

disk_build_ids_date() {
  [ -n "${DISK_BUILD_DATE}" ] || return 0
  case "${DISK_BUILD_DATE}" in
  [12][0-9][0-9][0-9][01][0-9][0-3][0-9][0-2][0-9][0-5][0-9][0-5][0-9]) return 0 ;;
  *)
    disk_error "--date takes YYYYMMDDhhmmss in UTC, such as 20091224180000, got: ${DISK_BUILD_DATE}"
    return 1
    ;;
  esac
}

disk_build_ids_level() {
  case "${DISK_BUILD_LEVEL}" in
  '' | [1-4]) return 0 ;;
  *)
    disk_error "--iso-level takes 1, 2, 3 or 4, got: ${DISK_BUILD_LEVEL}"
    return 1
    ;;
  esac
}

disk_build_mac_option() {
  for disk_bp_pair in "--boot:${DISK_BUILD_BOOT}" "--system-id:${DISK_BUILD_SYSTEM}" "--volume-set:${DISK_BUILD_VOLSET}" "--date:${DISK_BUILD_DATE}" "--iso-level:${DISK_BUILD_LEVEL}"; do
    [ -z "${disk_bp_pair#*:}" ] && continue
    printf '%s\n' "${disk_bp_pair%%:*}"
    return 0
  done
}

disk_build_mac_tool() {
  DISK_BUILD_XORRISO=n
  disk_bq_os="$(disk_os)"
  [ "${disk_bq_os}" = Darwin ] || return 0
  disk_bq_option="$(disk_build_mac_option)"
  [ -n "${disk_bq_option}" ] || return 0
  if [ "${DISK_BUILD_UDF}" = y ]; then
    disk_error "${disk_bq_option} on macOS is built with xorriso, which writes no UDF. leave udf out of --fs."
    return 1
  fi
  if command -v xorriso >/dev/null 2>&1; then
    DISK_BUILD_XORRISO=y
    return 0
  fi
  disk_error "${disk_bq_option} on macOS needs xorriso, since hdiutil makehybrid has no such field. install it with brew install xorriso."
  return 1
}

disk_build_ids_udf() {
  [ "${DISK_BUILD_UDF}" = y ] && [ -n "${DISK_BUILD_DATE}" ] || return 0
  disk_error "--date needs xorriso, and a UDF image on Linux is built with genisoimage. leave udf out of --fs or leave out --date."
  return 1
}

disk_build_ids_upper() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

disk_build_ids_case() {
  DISK_BUILD_PUBLISHER="$(disk_build_ids_upper "${DISK_BUILD_PUBLISHER}")"
  DISK_BUILD_PREPARER="$(disk_build_ids_upper "${DISK_BUILD_PREPARER}")"
  DISK_BUILD_APPLICATION="$(disk_build_ids_upper "${DISK_BUILD_APPLICATION}")"
  DISK_BUILD_SYSTEM="$(disk_build_ids_upper "${DISK_BUILD_SYSTEM}")"
}

disk_build_ids_check() {
  disk_build_ids_fits --publisher "${DISK_BUILD_PUBLISHER}" 128 || return 1
  disk_build_ids_fits --preparer "${DISK_BUILD_PREPARER}" 128 || return 1
  disk_build_ids_fits --application "${DISK_BUILD_APPLICATION}" 128 || return 1
  disk_build_ids_fits --system-id "${DISK_BUILD_SYSTEM}" 32 || return 1
  disk_build_ids_fits --volume-set "${DISK_BUILD_VOLSET}" 128 || return 1
  disk_build_ids_date || return 1
  disk_build_ids_level || return 1
  disk_build_ids_case
}

disk_build_ids_rows() {
  [ -z "${DISK_BUILD_PUBLISHER}" ] || printf 'Publisher     %s\n' "${DISK_BUILD_PUBLISHER}"
  [ -z "${DISK_BUILD_PREPARER}" ] || printf 'Preparer      %s\n' "${DISK_BUILD_PREPARER}"
  [ -z "${DISK_BUILD_APPLICATION}" ] || printf 'Application   %s\n' "${DISK_BUILD_APPLICATION}"
  [ -z "${DISK_BUILD_SYSTEM}" ] || printf 'System        %s\n' "${DISK_BUILD_SYSTEM}"
  [ -z "${DISK_BUILD_VOLSET}" ] || printf 'Volume set    %s\n' "${DISK_BUILD_VOLSET}"
  [ -z "${DISK_BUILD_DATE}" ] || printf 'Date          %s UTC\n' "${DISK_BUILD_DATE}"
  [ -z "${DISK_BUILD_LEVEL}" ] || printf 'ISO level     %s\n' "${DISK_BUILD_LEVEL}"
  return 0
}
