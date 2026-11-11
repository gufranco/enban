#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_drive_tools_has() {
  [ -z "${DISK_APP_DRIVE_NOTE}" ] && return 0
  DISK_APP_STATUS="There is no drive to $1."
  return 1
}

disk_drive_tools_say() {
  disk_dy_text="$("$@" 2>&1)" && disk_dy_status=0 || disk_dy_status=1
  disk_dy_last="$(printf '%s\n' "${disk_dy_text}" | sed -n '$p')"
  DISK_APP_STATUS="$(disk_tools_sentence "${disk_dy_last#enban: }")"
  return "${disk_dy_status}"
}

disk_tools_tab_close() {
  disk_job_busy && return 0
  disk_drive_tools_has close || return 0
  disk_app_ask "Close the session or the disc? session or disc" "session"
  DISK_CLOSE_FINALIZE=n
  [ "${DISK_APP_ANSWER}" != disc ] || DISK_CLOSE_FINALIZE=y
  disk_drive_tools_say disk_close_check || return 0
  disk_job_typed close || return 0
  disk_drive_tools_say disk_close_go || :
}

disk_tools_tab_speed() {
  disk_drive_tools_has "set the speed of" || return 0
  disk_app_ask "Read speed, such as 4 or max" "max"
  case "${DISK_APP_ANSWER}" in
  max | [1-9] | [1-9][0-9]) DISK_SPEED_WANTED="${DISK_APP_ANSWER}" ;;
  *)
    DISK_APP_STATUS="The speed must be a whole number of times or max."
    return 0
    ;;
  esac
  disk_drive_tools_say disk_speed_run || :
}

disk_tools_tab_region() {
  disk_drive_tools_has "read the region of" || return 0
  disk_app_ask "Region 1 to 8 to set, or empty to show it" ""
  case "${DISK_APP_ANSWER}" in
  '') disk_drive_tools_region_show ;;
  [1-8]) disk_drive_tools_region_set "${DISK_APP_ANSWER}" ;;
  *) DISK_APP_STATUS="The region must be a number from 1 to 8." ;;
  esac
}

disk_drive_tools_region_show() {
  disk_drive_tools_say disk_drive_tools_region_read || return 0
  DISK_APP_STATUS="$(printf '%s\n' "${disk_dy_last}" | awk -F '|' '{ printf "Region %s, %s changes left, %s.\n", $1, $2, $4 }')"
}

disk_drive_tools_region_read() {
  disk_raw_ready region || return 1
  disk_region_state || return 1
  printf '%s\n' "${DISK_REGION_STATE}"
}

disk_drive_tools_region_set() {
  disk_drive_tools_say disk_drive_tools_region_read || return 0
  DISK_REGION_STATE="${disk_dy_last}"
  disk_drive_tools_say disk_region_left || return 0
  DISK_REGION_SET="$1"
  disk_job_typed "change its region; ${DISK_REGION_WARNING}" || return 0
  disk_drive_tools_say disk_region_apply || :
}

disk_tools_tab_booktype() {
  disk_drive_tools_has "change the book type of" || return 0
  disk_app_ask "Book type: dvd-rom, dvd+r or dvd+rw" "dvd-rom"
  case "${DISK_APP_ANSWER}" in
  dvd-rom | dvd+r | dvd+rw) DISK_BOOKTYPE="${DISK_APP_ANSWER}" ;;
  *)
    DISK_APP_STATUS="The book type must be dvd-rom, dvd+r or dvd+rw."
    return 0
    ;;
  esac
  disk_drive_tools_say disk_booktype_ready || return 0
  disk_job_typed "change its book type" || return 0
  disk_drive_tools_say disk_booktype_go || :
}

disk_tools_tab_cue() {
  disk_app_ask "Folder with the WAV tracks" "path to a folder"
  disk_tc_folder="${DISK_APP_ANSWER%/}"
  disk_tc_tracks="$(find "${disk_tc_folder}" -maxdepth 1 -type f -name '*.wav' 2>/dev/null | LC_ALL=C sort)"
  if [ -z "${disk_tc_tracks}" ]; then
    DISK_APP_STATUS="No WAV files in ${disk_tc_folder}."
    return 0
  fi
  disk_app_ask "CUE file to create" "${disk_tc_folder}/album.cue"
  [ -n "${DISK_APP_ANSWER}" ] || return 0
  DISK_CUE_OUT="${DISK_APP_ANSWER}"
  DISK_CUE_TRACKS="${disk_tc_tracks}"
  disk_drive_tools_say disk_cue_run || :
}

disk_tools_tab_convert() {
  disk_job_busy && return 0
  disk_app_ask "Image to convert" "path to a .cue, .nrg, .mdf, .cdi or .img file"
  disk_tv_in="${DISK_APP_ANSWER}"
  disk_app_ask "ISO file to create" "path to a new .iso file"
  [ -n "${disk_tv_in}" ] && [ -n "${DISK_APP_ANSWER}" ] || return 0
  DISK_CONVERT_IN="${disk_tv_in}"
  DISK_CONVERT_OUT="${DISK_APP_ANSWER}"
  disk_job_launch disk_convert_run convert "${disk_tv_in} into ${DISK_APP_ANSWER}"
}
