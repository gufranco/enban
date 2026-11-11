#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_build_check() {
  if [ ! -d "${DISK_BUILD_SOURCE}" ]; then
    disk_error "no folder at ${DISK_BUILD_SOURCE}."
    return 1
  fi
  if [ -e "${DISK_BUILD_OUT}" ]; then
    disk_error "stopped: ${DISK_BUILD_OUT} already exists."
    return 1
  fi
  disk_build_fs "${DISK_BUILD_FS}" || return 1
  disk_build_label || return 1
  disk_build_tools
}

disk_build_fs() {
  DISK_BUILD_ISO=n
  DISK_BUILD_JOLIET=n
  DISK_BUILD_UDF=n
  for disk_bf_name in $(printf '%s\n' "$1" | tr ',' ' '); do
    case "${disk_bf_name}" in
    iso9660) DISK_BUILD_ISO=y ;;
    joliet) DISK_BUILD_JOLIET=y ;;
    udf) DISK_BUILD_UDF=y ;;
    *)
      disk_error "--fs takes iso9660, joliet and udf, got: ${disk_bf_name}"
      return 1
      ;;
    esac
  done
  [ "${DISK_BUILD_ISO}" = n ] || return 0
  disk_error "--fs needs iso9660, which every drive and system can read."
  return 1
}

disk_build_label() {
  disk_bl_label="${DISK_BUILD_LABEL:-${DISK_BUILD_SOURCE%/}}"
  disk_bl_label="${disk_bl_label##*/}"
  if [ "${#disk_bl_label}" -gt 32 ]; then
    disk_error "--label takes up to 32 characters, got ${#disk_bl_label}."
    return 1
  fi
  DISK_BUILD_VOLUME="$(printf '%s' "${disk_bl_label}" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9_' '_')"
}

disk_build_tools() {
  disk_bt_os="$(disk_os)"
  [ "${disk_bt_os}" != Darwin ] && [ "${DISK_BUILD_UDF}" = y ] || return 0
  command -v genisoimage >/dev/null 2>&1 && return 0
  disk_error "UDF on Linux needs genisoimage. install it, or leave udf out of --fs."
  return 1
}

disk_build_make() {
  disk_bm_part="$(mktemp "$(dirname "${DISK_BUILD_OUT}")/.enban-build.XXXXXX")" || return 1
  disk_bm_status=0
  case "$(disk_os)" in
  Darwin) disk_build_hybrid "${disk_bm_part}" || disk_bm_status=1 ;;
  *) disk_build_mkisofs "${disk_bm_part}" || disk_bm_status=1 ;;
  esac
  if [ "${disk_bm_status}" -eq 0 ] && mv "${disk_bm_part}" "${DISK_BUILD_OUT}"; then
    return 0
  fi
  rm -f "${disk_bm_part}" "${disk_bm_part}.iso"
  disk_error "unable to build ${DISK_BUILD_OUT} from ${DISK_BUILD_SOURCE}."
  return 1
}

disk_build_hybrid() {
  set -- "$1" -default-volume-name "${DISK_BUILD_VOLUME}"
  [ "${DISK_BUILD_ISO}" = n ] || set -- "$@" -iso
  [ "${DISK_BUILD_JOLIET}" = n ] || set -- "$@" -joliet
  [ "${DISK_BUILD_UDF}" = n ] || set -- "$@" -udf
  disk_bh_part="$1"
  shift
  rm -f "${disk_bh_part}"
  hdiutil makehybrid "$@" -o "${disk_bh_part}.iso" "${DISK_BUILD_SOURCE}" >/dev/null 2>&1 || return 1
  mv "${disk_bh_part}.iso" "${disk_bh_part}"
}

disk_build_mkisofs() {
  set -- "$1" -quiet -R -V "${DISK_BUILD_VOLUME}"
  [ "${DISK_BUILD_JOLIET}" = n ] || set -- "$@" -J
  disk_bk_part="$1"
  shift
  if [ "${DISK_BUILD_UDF}" = y ]; then
    genisoimage "$@" -udf -o "${disk_bk_part}" "${DISK_BUILD_SOURCE}" >/dev/null 2>&1
    return
  fi
  xorriso -as mkisofs "$@" -o "${disk_bk_part}" "${DISK_BUILD_SOURCE}" >/dev/null 2>&1
}

disk_build_names() {
  disk_bn_list="ISO9660"
  [ "${DISK_BUILD_JOLIET}" = n ] || disk_bn_list="${disk_bn_list}, Joliet"
  [ "${DISK_BUILD_UDF}" = n ] || disk_bn_list="${disk_bn_list}, UDF"
  printf '%s\n' "${disk_bn_list}"
}

disk_build_done() {
  disk_bd_files="$(find "${DISK_BUILD_SOURCE}" -type f | wc -l | tr -d '[:space:]')"
  disk_bd_bytes="$(wc -c <"${DISK_BUILD_OUT}" | tr -d '[:space:]')"
  disk_bd_names="$(disk_build_names)"
  printf 'Files         %s\nSectors       %s\n' "${disk_bd_files}" $((disk_bd_bytes / 2048))
  printf 'File systems  %s\n' "${disk_bd_names}"
  disk_bd_line="Done. ${DISK_BUILD_OUT} is built from ${DISK_BUILD_SOURCE}."
  if disk_ui_out; then
    disk_ui_done "${disk_bd_line}"
    return 0
  fi
  printf '%s\n' "${disk_bd_line}"
}

disk_build_run() {
  disk_build_check || return 1
  disk_build_make || return 1
  disk_build_done
}
