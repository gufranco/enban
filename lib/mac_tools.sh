#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_mac_cdrecord() {
  disk_mc_log="$(mktemp "${TMPDIR:-/tmp}/enban-cdrecord.XXXXXX")" || return 1
  disk_mc_status=0
  cdrecord "dev=${DISK_DRIVE}" "$@" >"${disk_mc_log}" 2>&1 || disk_mc_status=1
  disk_mc_reason="$(disk_drive_reason "${disk_mc_log}")"
  rm -f "${disk_mc_log}"
  [ "${disk_mc_status}" -eq 0 ] && return 0
  disk_error "the drive refused the command: ${disk_mc_reason:-cdrecord failed.}"
  return 1
}

disk_mac_tray() {
  case "${DISK_TRAY_ACTION}" in
  load)
    disk_mac_cdrecord -load || return 1
    disk_mt_line="Done. the tray of ${DISK_DRIVE} is closed and its disc loaded."
    ;;
  lock)
    disk_mac_cdrecord -lock || return 1
    disk_mt_line="Done. the tray of ${DISK_DRIVE} is locked until it is unlocked or the drive restarts."
    ;;
  *)
    disk_mac_cdrecord -load || return 1
    disk_mt_line="Done. the tray of ${DISK_DRIVE} is unlocked."
    ;;
  esac
  disk_raw_done "${disk_mt_line}"
}

disk_mac_close() {
  if [ "${DISK_CLOSE_TRACK}" = y ]; then
    disk_error "close --track needs sg_raw; on macOS cdrecord closes a session or the disc, never one track alone."
    return 1
  fi
  if [ "${DISK_CLOSE_FINALIZE}" = y ]; then
    disk_mac_cdrecord -fix -tao || return 1
    disk_raw_done "Done. the disc in ${DISK_DRIVE} is finalized."
    return 0
  fi
  disk_mac_cdrecord -fix -tao -multi || return 1
  disk_raw_done "Done. the session on ${DISK_DRIVE} is closed."
}

disk_mac_cd_speed() {
  if [ "${DISK_SPEED_WANTED}" = max ]; then
    printf '400\n'
    return 0
  fi
  disk_ms_unit="$(disk_speed_unit)"
  disk_ms_rate=$((DISK_SPEED_WANTED * disk_ms_unit))
  disk_ms_cd=$(((disk_ms_rate + 176) / 177))
  [ "${disk_ms_cd}" -ge 1 ] || disk_ms_cd=1
  printf '%s\n' "${disk_ms_cd}"
}

disk_mac_speed() {
  disk_mp_cd="$(disk_mac_cd_speed)"
  disk_mp_log="$(mktemp "${TMPDIR:-/tmp}/enban-readcd.XXXXXX")" || return 1
  disk_mp_status=0
  readcd "dev=${DISK_DRIVE}" "speed=${disk_mp_cd}" sectors=0-0 f=/dev/null >/dev/null 2>"${disk_mp_log}" || disk_mp_status=1
  disk_mp_reason="$(sed -n 's/^readcd: //p' "${disk_mp_log}" | sed -n '$p')"
  rm -f "${disk_mp_log}"
  if [ "${disk_mp_status}" -ne 0 ]; then
    disk_error "the drive refused the command: ${disk_mp_reason:-readcd failed.}"
    return 1
  fi
  disk_mp_line="Done. ${DISK_DRIVE} reads at its fastest."
  [ "${DISK_SPEED_WANTED}" = max ] || disk_mp_line="Done. ${DISK_DRIVE} reads at ${DISK_SPEED_WANTED}x."
  disk_raw_done "${disk_mp_line}"
}

disk_mac_features() {
  disk_mf_text="$(cdrecord "dev=${DISK_DRIVE}" -prcap -x 2>/dev/null)" || {
    disk_error "the drive refused the command: cdrecord could not read the feature list."
    return 1
  }
  printf '%s\n' "${disk_mf_text}" | awk -v names="${DISK_FEATURE_NAMES}" '
    BEGIN {
      split(names, known, "|")
      for (i in known) name[substr(known[i], 1, 4)] = substr(known[i], 6)
    }
    /^Feature: 0x[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f] / {
      code = tolower(substr($2, 3, 4))
      label = (code in name) ? name[code] : "unknown feature"
      printf "%s\t%s\t%s\n", code, label, (index($0, "(current)") ? "current" : "supported")
    }'
}

disk_mac_clone() {
  disk_mo_status=0
  readcd "dev=${DISK_DRIVE}" -clone "sectors=$2-$(($2 + $3))" "f=$1" "retries=${DISK_READ_RETRIES}" >/dev/null 2>"$1.err" || disk_mo_status=1
  DISK_MAC_BAD="$(grep -c 'not corrected' "$1.err" || true)"
  rm -f "$1.err" "$1.toc"
  return "${disk_mo_status}"
}

disk_mac_split() {
  disk_mx_at=0
  while [ "${disk_mx_at}" -lt "$2" ]; do
    disk_mx_count=$(($2 - disk_mx_at))
    [ "${disk_mx_count}" -le "${DISK_MAC_SPLIT}" ] || disk_mx_count="${DISK_MAC_SPLIT}"
    disk_mac_split_chunk "$1" "${disk_mx_at}" "${disk_mx_count}" "$3" "$4" || return 1
    disk_mx_at=$((disk_mx_at + disk_mx_count))
  done
}

disk_mac_split_chunk() {
  dd if="$1" of="$4.chunk" bs=2448 skip="$2" count="$3" 2>/dev/null || return 1
  disk_mk_text="$(od -An -v -to1 "$4.chunk" | awk -v want="$3" '
    { for (i = 1; i <= NF; i++) b[n++] = $i }
    END {
      if (n != want * 2448) exit 1
      for (s = 0; s < want; s++) {
        for (j = 0; j < 2352; j++) printf "\\0%s", b[s * 2448 + j]
      }
      printf "\n"
      for (s = 0; s < want; s++) {
        for (j = 2352; j < 2448; j++) printf "\\0%s", b[s * 2448 + j]
      }
      printf "\n"
    }')" || {
    rm -f "$4.chunk"
    return 1
  }
  rm -f "$4.chunk"
  disk_mk_main="$(printf '%s\n' "${disk_mk_text}" | sed -n '1p')"
  disk_mk_sub="$(printf '%s\n' "${disk_mk_text}" | sed -n '2p')"
  printf '%b' "${disk_mk_main}" >>"$4" || return 1
  [ -z "$5" ] || printf '%b' "${disk_mk_sub}" >>"$5"
}

disk_mac_disc_node() {
  disk_mn_text="$(drutil -drive "${DISK_DRIVE_PRODUCT}" status 2>/dev/null)" || disk_mn_text=""
  disk_mn_node="$(printf '%s\n' "${disk_mn_text}" | sed -n 's/.*Name: \(\/dev\/[A-Za-z0-9]*\).*/\1/p' | sed -n '1p')"
  if [ -z "${disk_mn_node}" ]; then
    disk_error "drutil names no disc device for ${DISK_DRIVE}, so its book type cannot be reached."
    return 1
  fi
  printf '%s\n' "${disk_mn_node}"
}

disk_mac_ccd_copy() {
  disk_mz_sub="$(disk_read_ccd_sub)"
  disk_job_note "${DISK_READ_OUT}" "${disk_mz_sub}"
  disk_mz_raw="$(mktemp "${TMPDIR:-/tmp}/enban-clone.XXXXXX")" || return 1
  if ! disk_mac_clone "${disk_mz_raw}" 0 "${DISK_DRIVE_READABLE}"; then
    rm -f "${disk_mz_raw}"
    disk_error "unable to read ${DISK_DRIVE} into ${DISK_READ_OUT}."
    return 1
  fi
  if [ "${DISK_MAC_BAD}" -gt 0 ] && [ "${DISK_READ_IGNORE}" = n ]; then
    rm -f "${disk_mz_raw}"
    disk_error "${DISK_MAC_BAD} sectors of ${DISK_DRIVE} could not be read; --ignore-errors keeps them as zeros."
    return 1
  fi
  : >"${DISK_READ_OUT}"
  : >"${disk_mz_sub}"
  disk_mz_status=0
  disk_mac_split "${disk_mz_raw}" "${DISK_DRIVE_READABLE}" "${DISK_READ_OUT}" "${disk_mz_sub}" || disk_mz_status=1
  rm -f "${disk_mz_raw}"
  [ "${disk_mz_status}" -eq 0 ] || return 1
  DISK_READ_BAD="${DISK_MAC_BAD}"
  [ "${DISK_READ_BAD}" -eq 0 ] || disk_warning "${DISK_READ_BAD} sectors of ${DISK_DRIVE} could not be read and are zeros in ${DISK_READ_OUT}."
}

disk_mac_ccd_verify() {
  disk_mv_raw="$(mktemp "${TMPDIR:-/tmp}/enban-clone.XXXXXX")" || return 1
  disk_mv_status=0
  disk_mac_clone "${disk_mv_raw}" 0 "${DISK_DRIVE_READABLE}" || disk_mv_status=1
  : >"${disk_mv_raw}.main"
  [ "${disk_mv_status}" -ne 0 ] || disk_mac_split "${disk_mv_raw}" "${DISK_DRIVE_READABLE}" "${disk_mv_raw}.main" "" || disk_mv_status=1
  [ "${disk_mv_status}" -ne 0 ] || cmp -s "${disk_mv_raw}.main" "${DISK_READ_OUT}" || disk_mv_status=1
  rm -f "${disk_mv_raw}" "${disk_mv_raw}.main"
  [ "${disk_mv_status}" -eq 0 ] && return 0
  disk_error "the copy in ${DISK_READ_OUT} does not match the disc in ${DISK_DRIVE}."
  return 1
}

disk_mac_sector() {
  if ! disk_mac_clone "$1.both" "${DISK_SECTOR_LBA}" 1; then
    rm -f "$1.both"
    disk_error "the drive refused the command: readcd could not read sector ${DISK_SECTOR_LBA}."
    return 1
  fi
}
