#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_audio_check() {
  if [ ! -f "${DISK_WRITE_IMAGE}" ]; then
    disk_error "no CUE sheet at ${DISK_WRITE_IMAGE}."
    return 1
  fi
  disk_drive_read "${DISK_DRIVE}" write || return 1
  case "${DISK_DRIVE_CODE}" in
  0009 | 000a) : ;;
  *)
    disk_ac_name="$(disk_drive_short_profile)"
    disk_error "stopped: an audio CD needs a blank CD-R or CD-RW, and the disc in ${DISK_DRIVE} is a ${disk_ac_name}."
    return 1
    ;;
  esac
  [ "${DISK_DRIVE_STATUS}" = blank ] && return 0
  disk_error "stopped: the disc in ${DISK_DRIVE} is not blank."
  return 1
}

disk_audio_burn() {
  disk_ab_log="$(mktemp "${TMPDIR:-/tmp}/enban-audio.XXXXXX")" || return 1
  set -- -v "dev=${DISK_DRIVE}" -dao
  [ -z "${DISK_WRITE_SPEED}" ] || set -- "$@" "speed=${DISK_WRITE_SPEED}"
  [ "${DISK_WRITE_EJECT}" = n ] || set -- "$@" -eject
  [ "${DISK_WRITE_TEST}" = n ] || set -- "$@" -dummy
  disk_ab_status=0
  cdrskin "$@" "cuefile=${DISK_WRITE_IMAGE}" >"${disk_ab_log}" 2>&1 || disk_ab_status=1
  disk_ab_reason="$(sed -n 's/^cdrskin: FATAL : //p' "${disk_ab_log}" | sed -n '1p')"
  rm -f "${disk_ab_log}"
  [ "${disk_ab_status}" -eq 0 ] && return 0
  disk_error "the audio burn to ${DISK_DRIVE} failed: ${disk_ab_reason:-cdrskin stopped.}"
  return 1
}

disk_audio_go() {
  disk_audio_burn || return 1
  if [ "${DISK_WRITE_TEST}" = y ]; then
    disk_write_tested
    return 0
  fi
  disk_ag_line="Done. ${DISK_DRIVE} is written as an audio CD."
  [ "${DISK_WRITE_EJECT}" = n ] || disk_ag_line="Done. ${DISK_DRIVE} is written as an audio CD and ejected."
  disk_raw_done "${disk_ag_line}"
}

disk_audio_run() {
  disk_audio_check || return 1
  disk_write_confirm || return 1
  disk_audio_go
}
