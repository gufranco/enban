#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_tools_list() {
  printf '%s\n' \
    "Erase disc|quick or full, rewritable media only|erase" \
    "Close|session, disc or track|close" \
    "Book type|DVD-ROM, DVD+R or DVD+RW|booktype" \
    "Read speed|set or reset|speed" \
    "Tray|eject, load, lock or unlock|tray" \
    "Capabilities|what this drive reads and writes|caps" \
    "Sector viewer|hex of any LBA, user data|sector" \
    "Region|read or change the DVD region|region" \
    "Speed memory|remembered speed per media ID|speeds" \
    "Create CUE|audio tracks, pregaps, CD-TEXT|cue" \
    "Convert|BIN/CUE, NRG, MDS, CDI, CCD to ISO|convert" \
    "Volume label|change an ISO's label in place|label" \
    "Checksum|MD5, SHA-1 and SHA-256|checksum" \
    "Layer break|show the IFO layer break of DVD Video|layer" \
    "Mount|attach an image read-only|mount" \
    "ReZero|move the head back to the start|rezero" \
    "Sync cache|write the drive's cache to the disc|sync"
}

disk_tools_field() {
  disk_tools_list | awk -F '|' -v i="$1" -v f="$2" 'NR == i + 1 { print $f }'
}

disk_tools_tab_key() {
  disk_job_key erase "$1" && return 0
  disk_job_key checksum "$1" && return 0
  disk_job_key convert "$1" && return 0
  case "${DISK_APP_T_OPEN}" in
  erase) disk_tools_tab_erase_key "$1" ;;
  caps | speeds) disk_tools_tab_caps_key "$1" ;;
  sector) disk_tools_tab_sector_key "$1" ;;
  *) disk_tools_tab_list_key "$1" ;;
  esac
}

disk_tools_tab_list_key() {
  case "$1" in
  up) [ "${DISK_APP_T_FOCUS}" -le 0 ] || DISK_APP_T_FOCUS=$((DISK_APP_T_FOCUS - 1)) ;;
  down) [ "${DISK_APP_T_FOCUS}" -ge 16 ] || DISK_APP_T_FOCUS=$((DISK_APP_T_FOCUS + 1)) ;;
  enter) disk_tools_tab_open ;;
  *) return 0 ;;
  esac
}

disk_tools_tab_open() {
  disk_to_action="$(disk_tools_field "${DISK_APP_T_FOCUS}" 3)"
  [ "${disk_to_action}" != caps ] || disk_tools_tab_caps_load
  case "${disk_to_action}" in
  erase | caps | speeds) DISK_APP_T_OPEN="${disk_to_action}" ;;
  tray) disk_tools_tab_tray ;;
  checksum) disk_tools_tab_checksum ;;
  sector) disk_tools_tab_sector_open ;;
  *) "disk_tools_tab_${disk_to_action}" ;;
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

disk_tools_tab_caps_load() {
  DISK_APP_T_FEATURES=""
  [ -z "${DISK_APP_DRIVE_NOTE}" ] || return 0
  if ! command -v sg_raw >/dev/null 2>&1; then
    DISK_APP_T_FEATURES=-
    return 0
  fi
  DISK_APP_T_FEATURES="$(disk_features_text 2>/dev/null)" || DISK_APP_T_FEATURES=""
}

disk_tools_tab_caps_key() {
  case "$1" in
  enter | esc) DISK_APP_T_OPEN="" ;;
  *) return 0 ;;
  esac
}

disk_tools_tab_sector_open() {
  DISK_APP_T_IMAGE=""
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    disk_app_ask "Image to view, as no drive is chosen" "path to an image"
    [ -n "${DISK_APP_ANSWER}" ] || return 0
    DISK_APP_T_IMAGE="${DISK_APP_ANSWER}"
  fi
  DISK_APP_T_LBA=0
  DISK_APP_T_PAGE=0
  DISK_APP_T_OPEN=sector
}

disk_tools_tab_sector_key() {
  disk_tk_last=7
  [ "${DISK_APP_T_RAW}" = n ] || disk_tk_last=9
  case "$1" in
  left) [ "${DISK_APP_T_LBA}" -le 0 ] || DISK_APP_T_LBA=$((DISK_APP_T_LBA - 1)) ;;
  right) DISK_APP_T_LBA=$((DISK_APP_T_LBA + 1)) ;;
  up) [ "${DISK_APP_T_PAGE}" -le 0 ] || DISK_APP_T_PAGE=$((DISK_APP_T_PAGE - 1)) ;;
  down) [ "${DISK_APP_T_PAGE}" -ge "${disk_tk_last}" ] || DISK_APP_T_PAGE=$((DISK_APP_T_PAGE + 1)) ;;
  m)
    DISK_APP_T_RAW="$(disk_job_flip "${DISK_APP_T_RAW}")"
    DISK_APP_T_SUB=n
    DISK_APP_T_PAGE=0
    ;;
  s)
    DISK_APP_T_SUB="$(disk_job_flip "${DISK_APP_T_SUB}")"
    [ "${DISK_APP_T_SUB}" = n ] || DISK_APP_T_RAW=y
    DISK_APP_T_PAGE=0
    ;;
  g) disk_tools_tab_sector_go ;;
  esc) DISK_APP_T_OPEN="" ;;
  *) return 0 ;;
  esac
}

disk_tools_tab_sector_go() {
  disk_app_ask "LBA to show" "${DISK_APP_T_LBA}"
  case "${DISK_APP_ANSWER}" in
  '' | *[!0-9]*) DISK_APP_STATUS="The LBA must be a whole number." ;;
  *)
    DISK_APP_T_LBA="${DISK_APP_ANSWER}"
    DISK_APP_T_PAGE=0
    ;;
  esac
}

disk_frame_tools_sector() {
  DISK_SECTOR_IMAGE="${DISK_APP_T_IMAGE}"
  DISK_SECTOR_LBA="${DISK_APP_T_LBA}"
  DISK_SECTOR_RAW="${DISK_APP_T_RAW}"
  DISK_SECTOR_SUB="${DISK_APP_T_SUB}"
  disk_fx_shown="$(disk_sector_run 2>&1)" || :
  disk_fx_first="$(printf '%s\n' "${disk_fx_shown}" | sed -n '1p')"
  case "${disk_fx_first}" in
  LBA*) : ;;
  *)
    disk_fx_reason="$(disk_tools_sentence "${disk_fx_first#enban: }")"
    printf '%s\n' "Sector viewer" "" "${disk_fx_reason}" "" "left/right sector   g go to LBA   esc back"
    return 0
    ;;
  esac
  printf 'Sector viewer   %s\n\n' "${disk_fx_first}"
  printf '%s\n' "${disk_fx_shown}" | sed -n "2p;$((DISK_APP_T_PAGE * 16 + 3)),$((DISK_APP_T_PAGE * 16 + 18))p"
  printf '%s\n' "${disk_fx_shown}" | sed -n '/^Decoded$/,$p'
  printf '\n%s\n' "left/right sector   up/down page   g go to LBA   m raw   s subchannel   esc back"
}

disk_tools_sentence() {
  printf '%s\n' "$1" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }'
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

disk_tools_tab_tray() {
  disk_app_ask "Tray: eject, load, lock or unlock" "eject"
  case "${DISK_APP_ANSWER}" in
  '' | eject) disk_tools_tab_eject ;;
  load | lock | unlock)
    disk_drive_tools_has "move the tray of" || return 0
    DISK_TRAY_ACTION="${DISK_APP_ANSWER}"
    disk_drive_tools_say disk_tray_run || :
    ;;
  *) DISK_APP_STATUS="The tray takes eject, load, lock or unlock." ;;
  esac
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
  disk_job_pane convert && return 0
  case "${DISK_APP_T_OPEN}" in
  erase) disk_frame_tools_erase ;;
  caps) disk_frame_tools_caps ;;
  speeds) disk_frame_tools_speeds ;;
  sector) disk_frame_tools_sector ;;
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
  printf '%s\n' "" "Features"
  case "${DISK_APP_T_FEATURES}" in
  '') printf '%s\n' "  The drive reports no features." ;;
  -) printf '%s\n' "  sg_raw from sg3-utils lists them." ;;
  *) printf '%s\n' "${DISK_APP_T_FEATURES}" | awk -F '\t' '{ printf "  0x%s  %-38s %s\n", $1, $2, $3 }' ;;
  esac
  printf '%s\n' "" "enter or esc back"
}
