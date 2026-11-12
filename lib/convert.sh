#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_convert_check() {
  if [ ! -f "${DISK_CONVERT_IN}" ]; then
    disk_error "no image at ${DISK_CONVERT_IN}."
    return 1
  fi
  if [ -e "${DISK_CONVERT_OUT}" ]; then
    disk_error "stopped: ${DISK_CONVERT_OUT} already exists."
    return 1
  fi
  disk_convert_companion || return 1
  if disk_iso_is "${DISK_CONVERT_IN}"; then
    disk_error "stopped: ${DISK_CONVERT_IN} is already an ISO image, so it needs no conversion."
    return 1
  fi
  disk_cc_tool=iat
  disk_cc_what="this image"
  case "${DISK_CONVERT_IN}" in
  *.cue | *.CUE)
    disk_cc_tool=bchunk
    disk_cc_what="a CUE image"
    ;;
  *) : ;;
  esac
  command -v "${disk_cc_tool}" >/dev/null 2>&1 && return 0
  disk_error "convert needs ${disk_cc_tool} for ${disk_cc_what}. install it and try again."
  return 1
}

disk_convert_data() {
  case "${DISK_CONVERT_IN}" in
  *.[mM][dD][sS]) printf '%s.mdf\n' "${DISK_CONVERT_IN%.*}" ;;
  *.[cC][cC][dD]) printf '%s.img\n' "${DISK_CONVERT_IN%.*}" ;;
  *) printf '%s\n' "${DISK_CONVERT_IN}" ;;
  esac
}

disk_convert_companion() {
  disk_cn_data="$(disk_convert_data)"
  [ -f "${disk_cn_data}" ] && return 0
  disk_error "${DISK_CONVERT_IN} describes its data in ${disk_cn_data}, which is not there."
  return 1
}

disk_convert_bin() {
  disk_cb_name="$(sed -n 's/^ *FILE *"\(.*\)" .*/\1/p' "${DISK_CONVERT_IN}" | sed -n '1p')"
  if [ -z "${disk_cb_name}" ]; then
    disk_error "${DISK_CONVERT_IN} names no BIN file."
    return 1
  fi
  case "${disk_cb_name}" in
  /*) printf '%s\n' "${disk_cb_name}" ;;
  *) printf '%s/%s\n' "$(dirname "${DISK_CONVERT_IN}")" "${disk_cb_name}" ;;
  esac
}

disk_convert_make() {
  case "${DISK_CONVERT_IN}" in
  *.cue | *.CUE)
    disk_cm_bin="$(disk_convert_bin)" || return 1
    bchunk "${disk_cm_bin}" "${DISK_CONVERT_IN}" "$1/track" >/dev/null 2>&1 && mv "$1/track01.iso" "$1/out.iso"
    ;;
  *)
    disk_cm_data="$(disk_convert_data)"
    iat -i "${disk_cm_data}" -o "$1/out.iso" --iso >/dev/null 2>&1
    ;;
  esac
}

disk_convert_run() {
  disk_convert_check || return 1
  disk_cr_dir="$(mktemp -d "${TMPDIR:-/tmp}/enban-convert.XXXXXX")" || return 1
  disk_cr_status=0
  disk_convert_make "${disk_cr_dir}" 2>"${disk_cr_dir}/errors" || disk_cr_status=1
  if [ "${disk_cr_status}" -eq 0 ] && [ -s "${disk_cr_dir}/out.iso" ] && mv "${disk_cr_dir}/out.iso" "${DISK_CONVERT_OUT}"; then
    rm -rf "${disk_cr_dir}"
    disk_raw_done "Done. ${DISK_CONVERT_OUT} is converted from ${DISK_CONVERT_IN}."
    return 0
  fi
  if [ -s "${disk_cr_dir}/errors" ]; then
    cat "${disk_cr_dir}/errors" >&2
  else
    disk_error "unable to convert ${DISK_CONVERT_IN} into ${DISK_CONVERT_OUT}."
  fi
  rm -rf "${disk_cr_dir}"
  return 1
}
