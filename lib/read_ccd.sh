#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_read_ccd_sub() {
  printf '%s.sub\n' "${DISK_READ_OUT%.*}"
}

disk_read_ccd_file() {
  printf '%s.ccd\n' "${DISK_READ_OUT%.*}"
}

disk_read_ccd_ready() {
  [ "${DISK_READ_CCD}" = y ] || return 0
  case "${DISK_READ_OUT}" in
  *.img) : ;;
  *)
    disk_error "--ccd writes a raw CloneCD image, so its name ends in .img, got: ${DISK_READ_OUT}"
    return 1
    ;;
  esac
  if [ "${DISK_READ_CUE}" = y ]; then
    disk_error "--ccd and --cue each write the layout file of the image; choose one."
    return 1
  fi
  case "${DISK_DRIVE_PROFILE}" in
  CD*) : ;;
  *)
    disk_error "--ccd reads a CD, and the disc in ${DISK_DRIVE} is ${DISK_DRIVE_PROFILE}."
    return 1
    ;;
  esac
  disk_read_ccd_free || return 1
  command -v sg_raw >/dev/null 2>&1 && return 0
  disk_error "--ccd needs sg_raw from sg3-utils to read raw sectors. install it and try again."
  return 1
}

disk_read_ccd_free() {
  disk_rf_sub="$(disk_read_ccd_sub)"
  disk_rf_ccd="$(disk_read_ccd_file)"
  for disk_rf_path in "${disk_rf_sub}" "${disk_rf_ccd}"; do
    [ ! -e "${disk_rf_path}" ] && continue
    disk_error "stopped: ${disk_rf_path} already exists."
    return 1
  done
}

disk_read_ccd_copy() {
  disk_rc_sub="$(disk_read_ccd_sub)"
  disk_job_note "${DISK_READ_OUT}" "${disk_rc_sub}"
  : >"${DISK_READ_OUT}" || return 1
  : >"${disk_rc_sub}" || return 1
  disk_rc_lba=0
  while [ "${disk_rc_lba}" -lt "${DISK_DRIVE_READABLE}" ]; do
    disk_rc_count=$((DISK_DRIVE_READABLE - disk_rc_lba))
    [ "${disk_rc_count}" -le "${DISK_READ_CCD_CHUNK}" ] || disk_rc_count="${DISK_READ_CCD_CHUNK}"
    disk_read_ccd_chunk "${disk_rc_lba}" "${disk_rc_count}" "${disk_rc_sub}" || return 1
    disk_rc_lba=$((disk_rc_lba + disk_rc_count))
  done
}

disk_read_ccd_chunk() {
  disk_rk_try=0
  while ! disk_read_ccd_fetch "$1" "$2" "$3"; do
    disk_rk_try=$((disk_rk_try + 1))
    [ "${disk_rk_try}" -gt "${DISK_READ_RETRIES}" ] || continue
    if [ "${DISK_READ_IGNORE}" = y ]; then
      disk_read_ccd_zeros "$@"
      return 0
    fi
    disk_read_drop
    disk_error "unable to read sectors $1 to $(($1 + $2 - 1)) of ${DISK_DRIVE} into ${DISK_READ_OUT}."
    return 1
  done
}

disk_read_ccd_zeros() {
  dd if=/dev/zero bs=2352 count="$2" 2>/dev/null >>"${DISK_READ_OUT}"
  dd if=/dev/zero bs=96 count="$2" 2>/dev/null >>"$3"
  DISK_READ_BAD=$((DISK_READ_BAD + $2))
  disk_warning "sectors $1 to $(($1 + $2 - 1)) of ${DISK_DRIVE} could not be read and are zeros in ${DISK_READ_OUT}."
}

disk_read_ccd_fetch() {
  disk_rh_main="$(mktemp "${TMPDIR:-/tmp}/enban-ccd.XXXXXX")" || return 1
  disk_rh_status=0
  disk_read_ccd_send "$1" "$2" main "${disk_rh_main}" &&
    disk_read_ccd_send "$1" "$2" sub "${disk_rh_main}.sub" &&
    cat "${disk_rh_main}" >>"${DISK_READ_OUT}" &&
    cat "${disk_rh_main}.sub" >>"$3" || disk_rh_status=1
  rm -f "${disk_rh_main}" "${disk_rh_main}.sub"
  return "${disk_rh_status}"
}

disk_read_ccd_send() {
  disk_rn_lba="$(printf '%08x' "$1" | sed 's/../& /g')"
  disk_rn_count="$(printf '%06x' "$2" | sed 's/../& /g')"
  case "$3" in
  main)
    disk_rn_size=2352
    disk_rn_select="f8 00"
    ;;
  *)
    disk_rn_size=96
    disk_rn_select="00 01"
    ;;
  esac
  disk_rn_want=$(($2 * disk_rn_size))
  # shellcheck disable=SC2086
  sg_raw -r "${disk_rn_want}" -o "$4" "${DISK_DRIVE#stdio:}" be 00 ${disk_rn_lba} ${disk_rn_count} ${disk_rn_select} 00 >/dev/null 2>&1 || return 1
  disk_rn_got="$(disk_file_bytes "$4")"
  [ "${disk_rn_got}" -eq "${disk_rn_want}" ]
}

disk_read_ccd_verify() {
  disk_cv_part="$(mktemp "${TMPDIR:-/tmp}/enban-ccd.XXXXXX")" || return 1
  disk_cv_lba=0
  disk_cv_status=0
  while [ "${disk_cv_lba}" -lt "${DISK_DRIVE_READABLE}" ] && [ "${disk_cv_status}" -eq 0 ]; do
    disk_cv_count=$((DISK_DRIVE_READABLE - disk_cv_lba))
    [ "${disk_cv_count}" -le "${DISK_READ_CCD_CHUNK}" ] || disk_cv_count="${DISK_READ_CCD_CHUNK}"
    disk_read_ccd_same "${disk_cv_lba}" "${disk_cv_count}" "${disk_cv_part}" || disk_cv_status=1
    disk_cv_lba=$((disk_cv_lba + disk_cv_count))
  done
  rm -f "${disk_cv_part}"
  [ "${disk_cv_status}" -eq 0 ] && return 0
  disk_error "the copy in ${DISK_READ_OUT} does not match the disc in ${DISK_DRIVE}."
  return 1
}

disk_read_ccd_same() {
  disk_read_ccd_send "$1" "$2" main "$3" || return 1
  dd if="${DISK_READ_OUT}" bs=2352 skip="$1" count="$2" 2>/dev/null | cmp -s - "$3"
}

disk_read_ccd_layout() {
  disk_rl_file="$(disk_read_ccd_file)"
  disk_rl_text="$(disk_read_ccd_text "${DISK_DRIVE_READABLE}")"
  printf '%s\n' "${disk_rl_text}" | awk '{ printf "%s\r\n", $0 }' >"${disk_rl_file}"
}

disk_read_ccd_text() {
  awk -v out="$1" '
    function entry(n, point, pmin, psec, pframe, plba) {
      printf "[Entry %d]\nSession=1\nPoint=0x%02x\nADR=0x01\nControl=0x04\nTrackNo=0\n", n, point
      printf "AMin=0\nASec=0\nAFrame=0\nALBA=-150\nZero=0\n"
      printf "PMin=%d\nPSec=%d\nPFrame=%d\nPLBA=%d\n\n", pmin, psec, pframe, plba
    }
    BEGIN {
      printf "[CloneCD]\nVersion=3\n\n[Disc]\nTocEntries=4\nSessions=1\nDataTracksScrambled=0\nCDTextLength=0\n\n"
      printf "[Session 1]\nPreGapMode=1\nPreGapSubC=0\n\n"
      entry(0, 160, 1, 0, 0, 4350)
      entry(1, 161, 1, 0, 0, 4350)
      end = out + 150
      entry(2, 162, int(end / 4500), int(end / 75) % 60, end % 75, out)
      entry(3, 1, 0, 2, 0, 0)
      printf "[TRACK 1]\nMODE=1\nINDEX 1=0"
    }'
}
