#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_read_tab_key() {
  disk_job_key read "$1" && return 0
  case "$1" in
  up) DISK_APP_R_FIELD=0 ;;
  down) DISK_APP_R_FIELD=1 ;;
  enter) disk_read_tab_edit ;;
  space) disk_read_tab_toggle ;;
  r) disk_read_tab_start ;;
  *) return 0 ;;
  esac
}

disk_read_tab_edit() {
  case "${DISK_APP_R_FIELD}" in
  0)
    disk_app_ask "Image file to create" "path to a new .iso file"
    disk_read_tab_out "${DISK_APP_ANSWER}"
    ;;
  *) disk_read_tab_toggle ;;
  esac
}

disk_read_tab_toggle() {
  [ "${DISK_APP_R_FIELD}" -eq 1 ] || return 0
  DISK_APP_R_VERIFY="$(disk_job_flip "${DISK_APP_R_VERIFY}")"
}

disk_read_tab_out() {
  [ -n "$1" ] || return 0
  if [ -e "$1" ]; then
    DISK_APP_STATUS="$1 already exists. Choose a new name."
    return 0
  fi
  DISK_APP_R_OUT="$1"
  DISK_APP_STATUS="Ready to read into $1. Press r to read."
}

disk_read_tab_start() {
  disk_job_busy && return 0
  if [ -z "${DISK_APP_R_OUT}" ]; then
    DISK_APP_STATUS="Choose an image file first: Enter on Image."
    return 0
  fi
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    DISK_APP_STATUS="There is no drive to read from."
    return 0
  fi
  DISK_READ_OUT="${DISK_APP_R_OUT}"
  DISK_WRITE_VERIFY="${DISK_APP_R_VERIFY}"
  disk_job_launch disk_read_run read "${DISK_DRIVE} into ${DISK_APP_R_OUT}"
}

disk_frame_read() {
  disk_job_pane read && return 0
  disk_fr_verify="$(disk_job_box "${DISK_APP_R_VERIFY}")"
  printf '%s\n' "Read disc to image" ""
  disk_job_row 0 "${DISK_APP_R_FIELD}" "Image" "${DISK_APP_R_OUT:-none chosen, press Enter}"
  disk_job_row 1 "${DISK_APP_R_FIELD}" "Verify" "${disk_fr_verify}"
  printf '%s\n' "" "enter edit   space toggle   r read"
}
