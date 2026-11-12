#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_raw_ready() {
  disk_drive_read "${DISK_DRIVE}" "$1" || return 1
  command -v sg_raw >/dev/null 2>&1 && return 0
  disk_error "$1 needs sg_raw from sg3-utils. install it and try again."
  return 1
}

disk_raw_send() {
  disk_rs_errors="$(mktemp "${TMPDIR:-/tmp}/enban-raw.XXXXXX")" || return 1
  disk_rs_status=0
  sg_raw "$@" >/dev/null 2>"${disk_rs_errors}" || disk_rs_status=1
  disk_rs_reason="$(sed -n '$p' "${disk_rs_errors}" | sed 's/^sg_raw: //')"
  rm -f "${disk_rs_errors}"
  [ "${disk_rs_status}" -eq 0 ] && return 0
  disk_error "the drive refused the command: ${disk_rs_reason:-sg_raw failed.}"
  return 1
}

disk_raw_device() {
  printf '%s\n' "${DISK_DRIVE#stdio:}"
}

disk_raw_typed() {
  disk_rt_name="$(disk_drive_word "${DISK_DRIVE}")"
  printf 'Type %s to %s, or anything else to stop: ' "${disk_rt_name}" "$1" >&2
  disk_rt_answer=""
  IFS= read -r disk_rt_answer || disk_rt_answer=""
  [ "${disk_rt_answer}" = "${disk_rt_name}" ] && return 0
  disk_error "cancelled, nothing was touched."
  return 1
}

disk_raw_done() {
  if disk_ui_out; then
    disk_ui_done "$1"
    return 0
  fi
  printf '%s\n' "$1"
}

disk_close_run() {
  disk_close_check || return 1
  disk_raw_typed "close it" || return 1
  disk_close_go
}

disk_close_check() {
  disk_raw_ready close || return 1
  [ "${DISK_DRIVE_STATUS}" = appendable ] && return 0
  disk_error "stopped: the disc in ${DISK_DRIVE} is ${DISK_DRIVE_STATUS}, so there is no session to close."
  return 1
}

disk_close_go() {
  if [ "${DISK_CLOSE_TRACK}" = y ]; then
    disk_close_track
    return
  fi
  disk_cr_how=02
  [ "${DISK_CLOSE_FINALIZE}" = n ] || disk_cr_how=04
  disk_cr_device="$(disk_raw_device)"
  disk_raw_send "${disk_cr_device}" 5b 01 "${disk_cr_how}" 00 00 00 00 00 00 00 || return 1
  disk_cr_line="Done. the session on ${DISK_DRIVE} is closed."
  [ "${DISK_CLOSE_FINALIZE}" = n ] || disk_cr_line="Done. the disc in ${DISK_DRIVE} is finalized."
  disk_raw_done "${disk_cr_line}"
}

disk_speed_unit() {
  case "${DISK_DRIVE_CODE}" in
  0008 | 0009 | 000a) printf '177\n' ;;
  004*) printf '4496\n' ;;
  *) printf '1385\n' ;;
  esac
}

disk_speed_run() {
  disk_raw_ready speed || return 1
  disk_sp_rate=65535
  if [ "${DISK_SPEED_WANTED}" != max ]; then
    disk_sp_unit="$(disk_speed_unit)"
    disk_sp_rate=$((DISK_SPEED_WANTED * disk_sp_unit))
    [ "${disk_sp_rate}" -le 65535 ] || disk_sp_rate=65535
  fi
  disk_sp_bytes="$(printf '%02x %02x' $((disk_sp_rate / 256)) $((disk_sp_rate % 256)))"
  disk_sp_device="$(disk_raw_device)"
  # shellcheck disable=SC2086
  disk_raw_send "${disk_sp_device}" bb 00 ${disk_sp_bytes} ff ff 00 00 00 00 00 00 || return 1
  disk_sp_line="Done. ${DISK_DRIVE} reads at its fastest."
  [ "${DISK_SPEED_WANTED}" = max ] || disk_sp_line="Done. ${DISK_DRIVE} reads at ${DISK_SPEED_WANTED}x, ${disk_sp_rate} kB/s."
  disk_raw_done "${disk_sp_line}"
}

disk_region_state() {
  disk_rg_file="$(mktemp "${TMPDIR:-/tmp}/enban-rpc.XXXXXX")" || return 1
  disk_rg_device="$(disk_raw_device)"
  if ! disk_raw_send -r 8 -o "${disk_rg_file}" "${disk_rg_device}" a4 00 00 00 00 00 00 00 00 08 08 00; then
    rm -f "${disk_rg_file}"
    return 1
  fi
  DISK_REGION_STATE="$(od -An -tu1 -v "${disk_rg_file}" | awk '
    { for (i = 1; i <= NF; i++) b[n++] = $i }
    END {
      region = "none set"
      mask = b[5]
      for (i = 0; i < 8; i++) { if (mask % 2 == 0) { region = i + 1; break } mask = int(mask / 2) }
      printf "%s|%d|%d|%s\n", region, b[4] % 8, int(b[4] / 8) % 8, (b[6] == 1 ? "RPC Phase II" : "RPC Phase I")
    }')"
  rm -f "${disk_rg_file}"
}

disk_region_show() {
  printf '%s\n' "${DISK_REGION_STATE}" | awk -F '|' '{
    printf "Region          %s\nChanges left    %s\nVendor resets   %s\nScheme          %s\n", $1, $2, $3, $4
  }'
}

disk_region_run() {
  disk_raw_ready region || return 1
  disk_region_state || return 1
  if [ -z "${DISK_REGION_SET}" ]; then
    disk_region_show
    return 0
  fi
  disk_region_change
}

disk_region_change() {
  disk_region_left || return 1
  printf '%s\n' "${DISK_REGION_WARNING}" >&2
  disk_raw_typed "change its region" || return 1
  disk_region_apply
}

disk_region_left() {
  disk_rl_left="$(printf '%s\n' "${DISK_REGION_STATE}" | cut -d '|' -f 2)"
  DISK_REGION_WARNING="This uses one of the ${disk_rl_left} changes left; at zero the region is fixed for good."
  [ "${disk_rl_left}" -ne 0 ] && return 0
  disk_error "stopped: ${DISK_DRIVE} has no region changes left."
  return 1
}

disk_region_apply() {
  disk_rc_file="$(mktemp "${TMPDIR:-/tmp}/enban-rpc.XXXXXX")" || return 1
  disk_rc_octal="$(printf '%03o' $((255 - (1 << (DISK_REGION_SET - 1)))))"
  printf '\000\006\000\000%b\000\000\000' "\\0${disk_rc_octal}" >"${disk_rc_file}"
  disk_rc_device="$(disk_raw_device)"
  disk_rc_status=0
  disk_raw_send -s 8 -i "${disk_rc_file}" "${disk_rc_device}" a3 00 00 00 00 00 00 00 00 08 06 00 || disk_rc_status=1
  rm -f "${disk_rc_file}"
  [ "${disk_rc_status}" -eq 0 ] || return 1
  disk_raw_done "Done. ${DISK_DRIVE} is set to region ${DISK_REGION_SET}."
}
