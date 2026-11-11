#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_verify_tab_key() {
  disk_job_key verify "$1" && return 0
  case "$1" in
  up) DISK_APP_V_FIELD=0 ;;
  down) DISK_APP_V_FIELD=1 ;;
  enter) disk_verify_tab_edit ;;
  space) disk_verify_tab_toggle ;;
  v) disk_verify_tab_start ;;
  *) return 0 ;;
  esac
}

disk_verify_tab_edit() {
  case "${DISK_APP_V_FIELD}" in
  1)
    disk_app_ask "Image to compare with the disc" "path to an .iso file"
    disk_verify_tab_image "${DISK_APP_ANSWER}"
    ;;
  *) disk_verify_tab_toggle ;;
  esac
}

disk_verify_tab_toggle() {
  [ "${DISK_APP_V_FIELD}" -eq 0 ] || return 0
  DISK_APP_V_AGAINST="$(disk_job_flip "${DISK_APP_V_AGAINST}")"
}

disk_verify_tab_image() {
  [ -n "$1" ] || return 0
  disk_job_image "$1" || return 0
  DISK_APP_V_IMAGE="$1"
  DISK_APP_STATUS="Ready to verify ${DISK_APP_IMAGE_SECTORS} sectors. Press v to verify."
}

disk_verify_tab_start() {
  disk_job_busy && return 0
  if [ "${DISK_APP_V_AGAINST}" = y ] && [ -z "${DISK_APP_V_IMAGE}" ]; then
    DISK_APP_STATUS="Choose an image first: Enter on Image."
    return 0
  fi
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    DISK_APP_STATUS="There is no drive to verify."
    return 0
  fi
  DISK_VERIFY_IMAGE=""
  [ "${DISK_APP_V_AGAINST}" != y ] || DISK_VERIFY_IMAGE="${DISK_APP_V_IMAGE}"
  disk_vt_what="${DISK_DRIVE}"
  [ -z "${DISK_VERIFY_IMAGE}" ] || disk_vt_what="${DISK_DRIVE} against ${DISK_VERIFY_IMAGE}"
  disk_job_launch disk_verify_run verify "${disk_vt_what}"
}

disk_frame_verify() {
  disk_job_pane verify && return 0
  disk_fv_against="$(disk_job_box "${DISK_APP_V_AGAINST}")"
  printf '%s\n' "Verify disc" ""
  disk_job_row 0 "${DISK_APP_V_FIELD}" "Compare" "${disk_fv_against}"
  disk_job_row 1 "${DISK_APP_V_FIELD}" "Image" "${DISK_APP_V_IMAGE:-none chosen, press Enter}"
  printf '%s\n' "" "enter edit   space toggle   v verify"
}
