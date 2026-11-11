#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_write_tab_key() {
  case "${DISK_APP_JOB}:$1" in
  running:c) disk_write_tab_cancel ;;
  running:*) return 0 ;;
  finished:enter) DISK_APP_JOB=idle ;;
  finished:*) return 0 ;;
  *) disk_write_tab_form_key "$1" ;;
  esac
}

disk_write_tab_form_key() {
  case "$1" in
  up) [ "${DISK_APP_W_FIELD}" -le 0 ] || DISK_APP_W_FIELD=$((DISK_APP_W_FIELD - 1)) ;;
  down) [ "${DISK_APP_W_FIELD}" -ge 3 ] || DISK_APP_W_FIELD=$((DISK_APP_W_FIELD + 1)) ;;
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
  *) disk_write_tab_toggle ;;
  esac
}

disk_write_tab_toggle() {
  case "${DISK_APP_W_FIELD}" in
  2) DISK_APP_W_VERIFY="$(disk_write_tab_flip "${DISK_APP_W_VERIFY}")" ;;
  3) DISK_APP_W_EJECT="$(disk_write_tab_flip "${DISK_APP_W_EJECT}")" ;;
  *) return 0 ;;
  esac
}

disk_write_tab_flip() {
  case "$1" in
  y) printf 'n\n' ;;
  *) printf 'y\n' ;;
  esac
}

disk_write_tab_image() {
  [ -n "$1" ] || return 0
  if [ ! -f "$1" ]; then
    DISK_APP_STATUS="No image at $1."
    return 0
  fi
  disk_wt_bytes="$(wc -c <"$1" | tr -d '[:space:]')"
  if [ "${disk_wt_bytes}" -eq 0 ] || [ $((disk_wt_bytes % 2048)) -ne 0 ]; then
    DISK_APP_STATUS="$1 is not a disc image: its size is not whole 2048-byte sectors."
    return 0
  fi
  DISK_APP_W_IMAGE="$1"
  DISK_APP_W_SECTORS=$((disk_wt_bytes / 2048))
  DISK_APP_STATUS="Ready to write ${DISK_APP_W_SECTORS} sectors. Press w to write."
}

disk_write_tab_speed() {
  case "$1" in
  *[!0-9]*) DISK_APP_STATUS="The speed must be a whole number, such as 8." ;;
  *) DISK_APP_W_SPEED="$1" ;;
  esac
}

disk_write_tab_start() {
  if [ -z "${DISK_APP_W_IMAGE}" ]; then
    DISK_APP_STATUS="Choose an image first: Enter on Image."
    return 0
  fi
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    DISK_APP_STATUS="There is no drive to write to."
    return 0
  fi
  disk_ws_name="${DISK_DRIVE##*/}"
  disk_app_ask "Type ${disk_ws_name} to write, or anything else to stop" "${disk_ws_name}"
  if [ "${DISK_APP_ANSWER}" != "${disk_ws_name}" ]; then
    DISK_APP_STATUS="Nothing was written."
    return 0
  fi
  disk_write_tab_launch
}

disk_write_tab_launch() {
  DISK_APP_JOB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enban-job.XXXXXX")" || return 0
  DISK_WRITE_IMAGE="${DISK_APP_W_IMAGE}"
  DISK_WRITE_SPEED="${DISK_APP_W_SPEED}"
  DISK_WRITE_VERIFY="${DISK_APP_W_VERIFY}"
  DISK_WRITE_EJECT="${DISK_APP_W_EJECT}"
  disk_write_tab_job "${DISK_APP_JOB_DIR}" &
  DISK_APP_JOB_PID=$!
  DISK_APP_JOB=running
  DISK_APP_STATUS="Writing. Press c to cancel."
}

disk_write_tab_job() {
  disk_wj_status=0
  disk_write_tab_steps >"$1/log" 2>&1 || disk_wj_status="$?"
  printf '%s\n' "${disk_wj_status}" >"$1/status"
}

disk_write_tab_steps() {
  disk_write_check || return 1
  disk_write_go
}

disk_write_tab_poll() {
  [ "${DISK_APP_JOB}" = running ] || return 0
  [ -f "${DISK_APP_JOB_DIR}/status" ] || return 0
  disk_wp_status="$(cat "${DISK_APP_JOB_DIR}/status")"
  DISK_APP_W_RESULT="$(cat "${DISK_APP_JOB_DIR}/log")"
  rm -rf "${DISK_APP_JOB_DIR}"
  DISK_APP_JOB=finished
  disk_app_drive
  DISK_APP_STATUS="The write failed; the result says why."
  [ "${disk_wp_status}" -ne 0 ] || DISK_APP_STATUS="$(printf '%s\n' "${DISK_APP_W_RESULT}" | sed -n '$p')"
}

disk_write_tab_cancel() {
  disk_wx_children="$(pgrep -P "${DISK_APP_JOB_PID}" 2>/dev/null || true)"
  # shellcheck disable=SC2086
  kill "${DISK_APP_JOB_PID}" ${disk_wx_children} 2>/dev/null || true
  wait "${DISK_APP_JOB_PID}" 2>/dev/null || true
  rm -rf "${DISK_APP_JOB_DIR}"
  DISK_APP_JOB=finished
  DISK_APP_W_RESULT="Cancelled while writing. The disc may be unusable."
  DISK_APP_STATUS="Cancelled."
}

disk_write_tab_box() {
  case "$1" in
  y) printf '[x] on' ;;
  *) printf '[ ] off' ;;
  esac
}

disk_frame_write() {
  case "${DISK_APP_JOB}" in
  running) printf '%s\n' "Writing" "" "${DISK_APP_W_IMAGE} to ${DISK_DRIVE}" "" "Press c to cancel." ;;
  finished) printf '%s\n' "Result" "" "${DISK_APP_W_RESULT}" "" "Press Enter for the form." ;;
  *) disk_frame_write_form ;;
  esac
}

disk_frame_write_form() {
  disk_fw_verify="$(disk_write_tab_box "${DISK_APP_W_VERIFY}")"
  disk_fw_eject="$(disk_write_tab_box "${DISK_APP_W_EJECT}")"
  printf '%s\n' "Write image to disc" ""
  disk_frame_write_row 0 "Image" "${DISK_APP_W_IMAGE:-none chosen, press Enter}"
  disk_fw_auto="chosen by the drive"
  disk_frame_write_row 1 "Speed" "${DISK_APP_W_SPEED:-${disk_fw_auto}}"
  disk_frame_write_row 2 "Verify" "${disk_fw_verify}"
  disk_frame_write_row 3 "Eject" "${disk_fw_eject}"
  printf '%s\n' "" "enter edit   space toggle   w write"
}

disk_frame_write_row() {
  disk_wr_mark="  "
  [ "$1" -ne "${DISK_APP_W_FIELD}" ] || disk_wr_mark="> "
  printf '%s%-11s%s\n' "${disk_wr_mark}" "$2" "$3"
}
