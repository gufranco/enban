#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_write_tab_key() {
  disk_job_key write "$1" && return 0
  case "$1" in
  up) [ "${DISK_APP_W_FIELD}" -le 0 ] || DISK_APP_W_FIELD=$((DISK_APP_W_FIELD - 1)) ;;
  down) [ "${DISK_APP_W_FIELD}" -ge 6 ] || DISK_APP_W_FIELD=$((DISK_APP_W_FIELD + 1)) ;;
  enter) disk_write_tab_edit ;;
  space) disk_write_tab_toggle ;;
  w) disk_write_tab_start ;;
  *) return 0 ;;
  esac
}

disk_write_tab_edit() {
  case "${DISK_APP_W_FIELD}" in
  0)
    disk_app_ask "Image to write" "path to an .iso file"
    disk_write_tab_image "${DISK_APP_ANSWER}"
    ;;
  1)
    disk_app_ask "Write speed, empty for the drive's choice" "8"
    disk_write_tab_speed "${DISK_APP_ANSWER}"
    ;;
  5)
    disk_app_ask "Copies to write, 1 to 100" "1"
    disk_write_tab_copies "${DISK_APP_ANSWER}"
    ;;
  *) disk_write_tab_toggle ;;
  esac
}

disk_write_tab_toggle() {
  case "${DISK_APP_W_FIELD}" in
  2) DISK_APP_W_VERIFY="$(disk_job_flip "${DISK_APP_W_VERIFY}")" ;;
  3) DISK_APP_W_EJECT="$(disk_job_flip "${DISK_APP_W_EJECT}")" ;;
  4) DISK_APP_W_TEST="$(disk_job_flip "${DISK_APP_W_TEST}")" ;;
  6) DISK_APP_W_DELETE="$(disk_job_flip "${DISK_APP_W_DELETE}")" ;;
  *) return 0 ;;
  esac
}

disk_write_tab_image() {
  [ -n "$1" ] || return 0
  disk_job_image "$1" || return 0
  DISK_APP_W_IMAGE="$1"
  DISK_APP_W_SECTORS="${DISK_APP_IMAGE_SECTORS}"
  DISK_APP_STATUS="Ready to write ${DISK_APP_W_SECTORS} sectors. Press w to write."
}

disk_write_tab_speed() {
  case "$1" in
  *[!0-9]*) DISK_APP_STATUS="The speed must be a whole number, such as 8." ;;
  *) DISK_APP_W_SPEED="$1" ;;
  esac
}

disk_write_tab_copies() {
  case "$1" in
  [1-9] | [1-9][0-9] | 100) DISK_APP_W_COPIES="$1" ;;
  *) DISK_APP_STATUS="The copies must be a whole number from 1 to 100." ;;
  esac
}

disk_write_tab_start() {
  disk_job_busy && return 0
  if [ -z "${DISK_APP_W_IMAGE}" ]; then
    DISK_APP_STATUS="Choose an image first: Enter on Image."
    return 0
  fi
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    DISK_APP_STATUS="There is no drive to write to."
    return 0
  fi
  disk_job_typed || return 0
  DISK_WRITE_IMAGE="${DISK_APP_W_IMAGE}"
  DISK_WRITE_SPEED="${DISK_APP_W_SPEED}"
  DISK_WRITE_VERIFY="${DISK_APP_W_VERIFY}"
  DISK_WRITE_EJECT="${DISK_APP_W_EJECT}"
  DISK_WRITE_TEST="${DISK_APP_W_TEST}"
  DISK_WRITE_COPIES="${DISK_APP_W_COPIES}"
  DISK_WRITE_DELETE="${DISK_APP_W_DELETE}"
  [ "${DISK_WRITE_COPIES}" -eq 1 ] || DISK_WRITE_EJECT=y
  disk_job_launch disk_write_tab_steps write "${DISK_APP_W_IMAGE} to ${DISK_DRIVE}"
}

disk_write_tab_steps() {
  disk_write_check || return 1
  disk_write_copies
}

disk_frame_write() {
  disk_job_pane write && return 0
  disk_fw_verify="$(disk_job_box "${DISK_APP_W_VERIFY}")"
  disk_fw_eject="$(disk_job_box "${DISK_APP_W_EJECT}")"
  disk_fw_test="$(disk_job_box "${DISK_APP_W_TEST}")"
  disk_fw_delete="[ ] no, the image is kept"
  [ "${DISK_APP_W_DELETE}" = n ] || disk_fw_delete="[x] the image, after the last copy"
  disk_fw_auto="chosen by the drive"
  printf '%s\n' "Write image to disc" ""
  disk_job_row 0 "${DISK_APP_W_FIELD}" "Image" "${DISK_APP_W_IMAGE:-none chosen, press Enter}"
  disk_job_row 1 "${DISK_APP_W_FIELD}" "Speed" "${DISK_APP_W_SPEED:-${disk_fw_auto}}"
  disk_job_row 2 "${DISK_APP_W_FIELD}" "Verify" "${disk_fw_verify}"
  disk_job_row 3 "${DISK_APP_W_FIELD}" "Eject" "${disk_fw_eject}"
  disk_job_row 4 "${DISK_APP_W_FIELD}" "Test mode" "${disk_fw_test}"
  disk_job_row 5 "${DISK_APP_W_FIELD}" "Copies" "${DISK_APP_W_COPIES}"
  disk_job_row 6 "${DISK_APP_W_FIELD}" "Delete" "${disk_fw_delete}"
  printf '%s\n' "" "enter edit   space toggle   w write"
}
