#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_build_check() {
  disk_build_sources || return 1
  if [ -e "${DISK_BUILD_OUT}" ]; then
    disk_error "stopped: ${DISK_BUILD_OUT} already exists."
    return 1
  fi
  disk_build_fs "${DISK_BUILD_FS}" || return 1
  disk_build_label || return 1
  disk_build_tools
}

disk_build_sources() {
  if [ -z "${DISK_BUILD_LAYOUT}" ]; then
    [ -d "${DISK_BUILD_SOURCE}" ] && return 0
    disk_error "no folder at ${DISK_BUILD_SOURCE}."
    return 1
  fi
  disk_bs_missing="$(printf '%s\n' "${DISK_BUILD_LAYOUT}" | cut -f 2 | disk_build_missing)"
  [ -z "${disk_bs_missing}" ] && return 0
  disk_error "no file or folder at ${disk_bs_missing}."
  return 1
}

disk_build_missing() {
  while IFS= read -r disk_bi_source; do
    [ -e "${disk_bi_source}" ] && continue
    printf '%s\n' "${disk_bi_source}"
    return 0
  done
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
  disk_bl_first="${DISK_BUILD_LAYOUT%%"${DISK_TAB}"*}"
  [ -n "${DISK_BUILD_LAYOUT}" ] || disk_bl_first="${DISK_BUILD_SOURCE%/}"
  disk_bl_label="${DISK_BUILD_LABEL:-${disk_bl_first}}"
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
  [ -z "${DISK_JOB_NOTE}" ] || printf '%s\n' "${disk_bm_part}" >"${DISK_JOB_NOTE}"
  disk_bm_status=0
  case "$(disk_os)" in
  Darwin) disk_build_hybrid "${disk_bm_part}" || disk_bm_status=1 ;;
  *) disk_build_mkisofs "${disk_bm_part}" || disk_bm_status=1 ;;
  esac
  if [ "${disk_bm_status}" -eq 0 ] && mv "${disk_bm_part}" "${DISK_BUILD_OUT}"; then
    return 0
  fi
  rm -f "${disk_bm_part}" "${disk_bm_part}.iso"
  disk_bm_from="${DISK_BUILD_SOURCE:-the layout}"
  disk_error "unable to build ${DISK_BUILD_OUT} from ${disk_bm_from}."
  return 1
}

disk_build_hybrid() {
  disk_bh_part="$1"
  disk_bh_from="${DISK_BUILD_SOURCE}"
  if [ -n "${DISK_BUILD_LAYOUT}" ]; then
    disk_bh_from="${disk_bh_part}.stage"
    disk_build_stage "${disk_bh_from}" || return 1
  fi
  set -- -default-volume-name "${DISK_BUILD_VOLUME}"
  [ "${DISK_BUILD_ISO}" = n ] || set -- "$@" -iso
  [ "${DISK_BUILD_JOLIET}" = n ] || set -- "$@" -joliet
  [ "${DISK_BUILD_UDF}" = n ] || set -- "$@" -udf
  rm -f "${disk_bh_part}"
  disk_bh_status=0
  hdiutil makehybrid "$@" -o "${disk_bh_part}.iso" "${disk_bh_from}" >/dev/null 2>&1 || disk_bh_status=1
  [ -z "${DISK_BUILD_LAYOUT}" ] || rm -rf "${disk_bh_from}"
  [ "${disk_bh_status}" -eq 0 ] || return 1
  mv "${disk_bh_part}.iso" "${disk_bh_part}"
}

disk_build_stage() {
  mkdir "$1" || return 1
  printf '%s\n' "${DISK_BUILD_LAYOUT}" | cut -f 1,2 | disk_build_copy "$1"
}

disk_build_copy() {
  while IFS="${DISK_TAB}" read -r disk_bc_name disk_bc_source; do
    cp -cR "${disk_bc_source}" "$1/${disk_bc_name}" 2>/dev/null && continue
    cp -R "${disk_bc_source}" "$1/${disk_bc_name}" || return 1
  done
}

disk_build_mkisofs() {
  disk_bk_part="$1"
  disk_bk_grafts="$(disk_build_grafts)"
  set -- -quiet -R -V "${DISK_BUILD_VOLUME}" -graft-points
  [ "${DISK_BUILD_JOLIET}" = n ] || set -- "$@" -J
  [ "${DISK_BUILD_UDF}" = n ] || set -- "$@" -udf
  set -- "$@" -o "${disk_bk_part}" -path-list "${disk_bk_part}.grafts"
  printf '%s\n' "${disk_bk_grafts}" >"${disk_bk_part}.grafts"
  disk_bk_status=0
  if [ "${DISK_BUILD_UDF}" = y ]; then
    genisoimage "$@" >/dev/null 2>&1 || disk_bk_status=1
  else
    xorriso -as mkisofs "$@" >/dev/null 2>&1 || disk_bk_status=1
  fi
  rm -f "${disk_bk_part}.grafts"
  return "${disk_bk_status}"
}

disk_build_grafts() {
  if [ -z "${DISK_BUILD_LAYOUT}" ]; then
    printf '%s\n' "${DISK_BUILD_SOURCE}" | sed -e 's/[\\=]/\\&/g' -e 's|^|/=|'
    return 0
  fi
  printf '%s\n' "${DISK_BUILD_LAYOUT}" | sed -e 's/[\\=]/\\&/g' -e "s/${DISK_TAB}/=/" -e "s/${DISK_TAB}.*//"
}

disk_build_names() {
  disk_bn_list="ISO9660"
  [ "${DISK_BUILD_JOLIET}" = n ] || disk_bn_list="${disk_bn_list}, Joliet"
  [ "${DISK_BUILD_UDF}" = n ] || disk_bn_list="${disk_bn_list}, UDF"
  printf '%s\n' "${disk_bn_list}"
}

disk_build_done() {
  disk_bd_files="$(disk_build_count)"
  disk_bd_bytes="$(wc -c <"${DISK_BUILD_OUT}" | tr -d '[:space:]')"
  disk_bd_names="$(disk_build_names)"
  printf 'Files         %s\nSectors       %s\n' "${disk_bd_files}" $((disk_bd_bytes / 2048))
  printf 'File systems  %s\n' "${disk_bd_names}"
  disk_bd_from="${DISK_BUILD_SOURCE}"
  [ -z "${DISK_BUILD_LAYOUT}" ] || disk_bd_from="$(disk_build_entries)"
  disk_bd_line="Done. ${DISK_BUILD_OUT} is built from ${disk_bd_from}."
  if disk_ui_out; then
    disk_ui_done "${disk_bd_line}"
    return 0
  fi
  printf '%s\n' "${disk_bd_line}"
}

disk_build_entries() {
  disk_be_count="$(printf '%s\n' "${DISK_BUILD_LAYOUT}" | wc -l | tr -d '[:space:]')"
  case "${disk_be_count}" in
  1) printf '1 entry\n' ;;
  *) printf '%s entries\n' "${disk_be_count}" ;;
  esac
}

disk_build_count() {
  if [ -z "${DISK_BUILD_LAYOUT}" ]; then
    find "${DISK_BUILD_SOURCE}" -type f | wc -l | tr -d '[:space:]'
    return 0
  fi
  printf '%s\n' "${DISK_BUILD_LAYOUT}" | cut -f 2 | disk_build_count_files
}

disk_build_count_files() {
  while IFS= read -r disk_bf_source; do
    find "${disk_bf_source}" -type f
  done | wc -l | tr -d '[:space:]'
}

disk_build_run() {
  disk_build_check || return 1
  disk_build_make || return 1
  disk_build_done
}
