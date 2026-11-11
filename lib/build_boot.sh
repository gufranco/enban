#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_build_boot_check() {
  if [ -z "${DISK_BUILD_BOOT}" ]; then
    [ -z "${DISK_BOOT_OPTION}" ] && return 0
    disk_error "${DISK_BOOT_OPTION} needs --boot FILE, the boot image."
    return 1
  fi
  disk_build_boot_file || return 1
  disk_build_boot_emulation || return 1
  disk_build_boot_platform || return 1
  disk_build_boot_load
}

disk_build_boot_file() {
  [ -f "${DISK_BUILD_BOOT}" ] && [ -r "${DISK_BUILD_BOOT}" ] && return 0
  disk_error "no boot image to read at ${DISK_BUILD_BOOT}."
  return 1
}

disk_build_boot_emulation() {
  case "${DISK_BUILD_EMULATION}" in
  none) return 0 ;;
  floppy) disk_build_boot_floppy ;;
  hard-disk) disk_build_boot_mbr ;;
  *)
    disk_error "--emulation takes none, floppy or hard-disk, got: ${DISK_BUILD_EMULATION}"
    return 1
    ;;
  esac
}

disk_build_boot_floppy() {
  disk_bo_bytes="$(disk_file_bytes "${DISK_BUILD_BOOT}")"
  case "${disk_bo_bytes}" in
  1228800 | 1474560 | 2949120) return 0 ;;
  *)
    disk_error "a floppy boot image holds 1228800, 1474560 or 2949120 bytes, and ${DISK_BUILD_BOOT} holds ${disk_bo_bytes}."
    return 1
    ;;
  esac
}

disk_build_boot_mbr() {
  disk_bv_mark="$(od -An -tx1 -j 510 -N 2 "${DISK_BUILD_BOOT}" 2>/dev/null | tr -d ' \n')"
  [ "${disk_bv_mark}" = 55aa ] && return 0
  disk_error "a hard disk boot image starts with a master boot record, and ${DISK_BUILD_BOOT} has none."
  return 1
}

disk_build_boot_platform() {
  case "${DISK_BUILD_PLATFORM}" in
  x86 | efi | ppc | mac) return 0 ;;
  *)
    disk_error "--platform takes x86, efi, ppc or mac, got: ${DISK_BUILD_PLATFORM}"
    return 1
    ;;
  esac
}

disk_build_boot_load() {
  [ -n "${DISK_BUILD_LOAD}" ] || return 0
  if [ "${DISK_BUILD_EMULATION}" != none ]; then
    disk_error "--load-sectors works with --emulation none; a floppy or hard disk image is loaded whole."
    return 1
  fi
  case "${DISK_BUILD_LOAD}" in
  *[!0-9]* | 0*) : ;;
  *) [ "${DISK_BUILD_LOAD}" -gt 65535 ] || return 0 ;;
  esac
  disk_error "--load-sectors takes a whole number from 1 to 65535, got: ${DISK_BUILD_LOAD}"
  return 1
}

disk_build_boot_tool() {
  [ -n "${DISK_BUILD_BOOT}" ] && [ "${DISK_BUILD_UDF}" = y ] || return 0
  case "${DISK_BUILD_PLATFORM}" in
  x86 | efi) return 0 ;;
  *)
    disk_error "--platform ${DISK_BUILD_PLATFORM} needs xorriso, and a UDF image on Linux is built with genisoimage, which boots x86 and efi only. leave udf out of --fs."
    return 1
    ;;
  esac
}

disk_build_boot_exec() {
  DISK_BUILD_BOOT_COPY="$1.boot"
  disk_bx_grafts="$1.grafts"
  shift
  if [ -z "${DISK_BUILD_BOOT}" ]; then
    "$@"
    return
  fi
  cp "${DISK_BUILD_BOOT}" "${DISK_BUILD_BOOT_COPY}" || return 1
  printf '%s\n' "${DISK_BUILD_BOOT_COPY}" | sed -e 's/[\\=]/\\&/g' -e 's|^|enban.boot=|' >>"${disk_bx_grafts}"
  case "$1" in
  genisoimage) disk_build_boot_genisoimage "$@" ;;
  *) disk_build_boot_xorriso "$@" ;;
  esac
}

disk_build_boot_genisoimage() {
  disk_bg_entry=-b
  [ "${DISK_BUILD_PLATFORM}" = x86 ] || disk_bg_entry=-e
  set -- "$@" -hide enban.boot -hide-joliet enban.boot -hide enban.cat -hide-joliet enban.cat
  disk_build_boot_entry "$@" "${disk_bg_entry}" enban.boot
}

disk_build_boot_xorriso() {
  case "${DISK_BUILD_PLATFORM}" in
  ppc) disk_bj_platform=PPC ;;
  mac) disk_bj_platform=Mac ;;
  *) disk_bj_platform="${DISK_BUILD_PLATFORM}" ;;
  esac
  set -- "$@" -hide "${DISK_BUILD_BOOT_COPY}" -hide-joliet "${DISK_BUILD_BOOT_COPY}" --boot-catalog-hide
  disk_build_boot_entry "$@" -eltorito-platform "${disk_bj_platform}" -b enban.boot
}

disk_build_boot_entry() {
  set -- "$@" -c enban.cat
  case "${DISK_BUILD_EMULATION}" in
  none) set -- "$@" -no-emul-boot -boot-load-size "${DISK_BUILD_LOAD:-4}" ;;
  hard-disk) set -- "$@" -hard-disk-boot ;;
  *) : ;;
  esac
  [ "${DISK_BUILD_INFO}" = n ] || set -- "$@" -boot-info-table
  "$@"
}

disk_build_boot_rows() {
  [ -n "${DISK_BUILD_BOOT}" ] || return 0
  case "${DISK_BUILD_EMULATION}" in
  none) disk_by_mode="no emulation" ;;
  floppy) disk_by_mode="floppy emulation" ;;
  *) disk_by_mode="hard disk emulation" ;;
  esac
  printf 'Boot          %s, %s, %s\n' "${DISK_BUILD_BOOT##*/}" "${disk_by_mode}" "${DISK_BUILD_PLATFORM}"
}
