#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_tools_list() {
  printf '%s\n' \
    "Erase disc|quick or full, rewritable media only|erase" \
    "Close|track, session or disc|scsi" \
    "Book type|next write, this disc, or the drive|scsi" \
    "Read speed|set or reset|scsi" \
    "Tray|eject the disc|tray" \
    "Capabilities|what this drive reads and writes|caps" \
    "Sector viewer|hex of any LBA, user data or raw 2352|scsi" \
    "Region|read or change the DVD region|scsi" \
    "Speed memory|remembered speed per media ID|settings" \
    "Create CUE|audio tracks, pregaps, CD-TEXT|cue" \
    "Convert|BIN/CUE, NRG, MDS, CDI, CCD to ISO|cue" \
    "Volume label|change an ISO's label in place|later" \
    "Checksum|MD5, SHA-1 and SHA-256|checksum" \
    "Layer break|show the IFO layer break of DVD Video|later" \
    "Mount|attach an image read-only|later"
}

disk_tools_field() {
  disk_tools_list | awk -F '|' -v i="$1" -v f="$2" 'NR == i + 1 { print $f }'
}

disk_tools_tab_key() {
  disk_job_key erase "$1" && return 0
  disk_job_key checksum "$1" && return 0
  case "${DISK_APP_T_OPEN}" in
  erase) disk_tools_tab_erase_key "$1" ;;
  caps) disk_tools_tab_caps_key "$1" ;;
  *) disk_tools_tab_list_key "$1" ;;
  esac
}

disk_tools_tab_list_key() {
  case "$1" in
  up) [ "${DISK_APP_T_FOCUS}" -le 0 ] || DISK_APP_T_FOCUS=$((DISK_APP_T_FOCUS - 1)) ;;
  down) [ "${DISK_APP_T_FOCUS}" -ge 14 ] || DISK_APP_T_FOCUS=$((DISK_APP_T_FOCUS + 1)) ;;
  enter) disk_tools_tab_open ;;
  *) return 0 ;;
  esac
}

disk_tools_tab_open() {
  disk_to_action="$(disk_tools_field "${DISK_APP_T_FOCUS}" 3)"
  disk_to_name="$(disk_tools_field "${DISK_APP_T_FOCUS}" 1)"
  case "${disk_to_action}" in
  erase | caps) DISK_APP_T_OPEN="${disk_to_action}" ;;
  tray) disk_tools_tab_eject ;;
  checksum) disk_tools_tab_checksum ;;
  scsi) DISK_APP_STATUS="${disk_to_name} arrives with the raw SCSI tools." ;;
  cue) DISK_APP_STATUS="${disk_to_name} arrives with audio CD and CUE support." ;;
  settings) DISK_APP_STATUS="${disk_to_name} arrives with the log and settings." ;;
  *) DISK_APP_STATUS="${disk_to_name} arrives in a coming release." ;;
  esac
}

disk_tools_tab_erase_key() {
  case "$1" in
  space) DISK_APP_T_FULL="$(disk_job_flip "${DISK_APP_T_FULL}")" ;;
  enter) disk_tools_tab_erase ;;
  esc) DISK_APP_T_OPEN="" ;;
  *) return 0 ;;
  esac
}

disk_tools_tab_caps_key() {
  case "$1" in
  enter | esc) DISK_APP_T_OPEN="" ;;
  *) return 0 ;;
  esac
}

disk_tools_tab_erase() {
  disk_job_busy && return 0
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    DISK_APP_STATUS="There is no drive to erase."
    return 0
  fi
  disk_job_typed erase || return 0
  DISK_ERASE_FULL="${DISK_APP_T_FULL}"
  disk_job_launch disk_tools_tab_erase_steps erase "the disc in ${DISK_DRIVE}"
}

disk_tools_tab_erase_steps() {
  disk_erase_check || return 1
  disk_erase_go
}

disk_tools_tab_eject() {
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    DISK_APP_STATUS="There is no drive to eject."
    return 0
  fi
  if xorriso -outdev "${DISK_DRIVE}" -eject all >/dev/null 2>&1; then
    DISK_APP_STATUS="The tray of ${DISK_DRIVE} is open."
    return 0
  fi
  DISK_APP_STATUS="The tray of ${DISK_DRIVE} did not open."
}

disk_tools_tab_checksum() {
  disk_job_busy && return 0
  disk_app_ask "Image to check, empty for the disc in the drive" "path to an image"
  DISK_CHECKSUM_IMAGE="${DISK_APP_ANSWER}"
  if [ -z "${DISK_CHECKSUM_IMAGE}" ] && [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    DISK_APP_STATUS="There is no drive to check."
    return 0
  fi
  disk_tc_what="${DISK_CHECKSUM_IMAGE:-the disc in ${DISK_DRIVE}}"
  disk_job_launch disk_checksum_run checksum "${disk_tc_what}"
}

disk_frame_tools() {
  disk_job_pane erase && return 0
  disk_job_pane checksum && return 0
  case "${DISK_APP_T_OPEN}" in
  erase) disk_frame_tools_erase ;;
  caps) disk_frame_tools_caps ;;
  *) disk_frame_tools_list ;;
  esac
}

disk_frame_tools_list() {
  printf '%s\n' "Tools" "" "Drive"
  disk_tools_list | awk -F '|' -v focus="${DISK_APP_T_FOCUS}" '
    NR == 10 { print ""; print "Image" }
    { printf "%s%-15s %s\n", (NR - 1 == focus ? "> " : "  "), $1, $2 }'
  printf '%s\n' "" "enter open   arrows move"
}

disk_frame_tools_erase() {
  disk_fe_method=quick
  [ "${DISK_APP_T_FULL}" = n ] || disk_fe_method=full
  disk_fe_disc="${DISK_DRIVE:-no drive chosen}"
  printf '%s\n' "Erase disc" ""
  printf 'Disc       %s\n' "${disk_fe_disc}"
  printf 'Method     %s\n' "${disk_fe_method}"
  printf '%s\n' "" "Everything on the disc is lost."
  [ "${DISK_APP_T_FULL}" = n ] || printf '%s\n' "A full erase rewrites every sector and takes much longer."
  printf '%s\n' "" "space quick or full   enter erase   esc back"
}

disk_frame_tools_caps() {
  printf '%s\n' "Capabilities" ""
  if [ -z "${DISK_DRIVE_MEDIA}" ] || [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    printf '%s\n' "The drive reports nothing it can read or write."
  else
    printf '%s\n' "${DISK_DRIVE_MEDIA}" | sed 's/^/  /'
  fi
  printf '%s\n' "" "enter or esc back"
}
