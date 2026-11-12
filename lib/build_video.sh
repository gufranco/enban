#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_build_video_root() {
  if [ -z "${DISK_BUILD_LAYOUT}" ]; then
    [ -d "${DISK_BUILD_SOURCE%/}/VIDEO_TS" ]
    return
  fi
  disk_vq_dir="$(printf '%s\n' "${DISK_BUILD_LAYOUT}" | awk -F "${DISK_TAB}" '$1 == "VIDEO_TS" { print $2; exit }')"
  [ -n "${disk_vq_dir}" ] && [ -d "${disk_vq_dir}" ]
}

disk_build_video_check() {
  [ "${DISK_BUILD_DVD}" = y ] || return 0
  if ! disk_build_video_root; then
    disk_error "--dvd-video needs a VIDEO_TS folder at the root of the disc."
    return 1
  fi
  if [ "${DISK_BUILD_UDF}" = n ]; then
    disk_error "--dvd-video needs udf in --fs, since a DVD player reads the disc through UDF."
    return 1
  fi
  [ -z "${DISK_BUILD_BOOT}" ] && return 0
  disk_error "--dvd-video and --boot do not go together: a DVD Video disc does not boot."
  return 1
}

disk_build_video_grafts() {
  if [ "${DISK_BUILD_DVD}" = n ] || [ -z "${DISK_BUILD_LAYOUT}" ]; then
    disk_build_grafts
    return
  fi
  disk_build_stage "$1.stage" || return 1
  printf '%s\n' "$1.stage" | sed -e 's/[\\=]/\\&/g' -e 's|^|/=|'
}

disk_build_udf_tool() {
  disk_vu_os="$(disk_os)"
  case "${disk_vu_os}" in
  Darwin) printf 'mkisofs\n' ;;
  *) printf 'genisoimage\n' ;;
  esac
}

disk_build_video_rows() {
  [ "${DISK_BUILD_DVD}" = y ] || return 0
  printf 'Video         DVD Video, VIDEO_TS in player order\n'
  disk_build_video_layer
}

disk_build_video_layer() {
  disk_vl_bytes="$(disk_file_bytes "${DISK_BUILD_OUT}")"
  DISK_LAYER_TOTAL=$((disk_vl_bytes / 2048))
  [ "${DISK_LAYER_TOTAL}" -gt "${DISK_LAYER_SINGLE}" ] || return 0
  DISK_LAYER_IMAGE="${DISK_BUILD_OUT}"
  disk_vl_pick="$(disk_layer_starts | disk_layer_pick)"
  disk_vl_set="${disk_vl_pick#* }"
  disk_vl_where="a cell start in ${disk_vl_set}"
  [ "${disk_vl_set}" != - ] || disk_vl_where="the middle, since no cell starts near it"
  printf 'Layer break   sector %s, %s\n' "${disk_vl_pick% *}" "${disk_vl_where}"
}
