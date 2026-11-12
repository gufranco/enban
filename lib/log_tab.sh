#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_log_tab_key() {
  case "$1" in
  f) DISK_APP_L_LEVEL="$(disk_log_tab_next "${DISK_APP_L_LEVEL}")" ;;
  slash)
    disk_app_ask "Show only the lines that hold" "${DISK_APP_L_SEARCH}"
    DISK_APP_L_SEARCH="${DISK_APP_ANSWER}"
    ;;
  s) disk_log_tab_save ;;
  *) return 0 ;;
  esac
}

disk_log_tab_next() {
  case "$1" in
  all) printf 'warn\n' ;;
  warn) printf 'error\n' ;;
  *) printf 'all\n' ;;
  esac
}

disk_log_tab_save() {
  disk_app_ask "File to save the log to" "path to a new .log file"
  [ -n "${DISK_APP_ANSWER}" ] || return 0
  if [ -e "${DISK_APP_ANSWER}" ]; then
    DISK_APP_STATUS="${DISK_APP_ANSWER} already exists. Choose a new name."
    return 0
  fi
  if cat "${DISK_APP_LOG}" >"${DISK_APP_ANSWER}" 2>/dev/null; then
    DISK_APP_STATUS="Saved the log to ${DISK_APP_ANSWER}."
    return 0
  fi
  DISK_APP_STATUS="Unable to save the log to ${DISK_APP_ANSWER}."
}

disk_frame_log() {
  disk_fl_shown="everything"
  [ "${DISK_APP_L_LEVEL}" != warn ] || disk_fl_shown="warnings and errors"
  [ "${DISK_APP_L_LEVEL}" != error ] || disk_fl_shown="errors"
  [ -z "${DISK_APP_L_SEARCH}" ] || disk_fl_shown="${disk_fl_shown}, matching ${DISK_APP_L_SEARCH}"
  printf 'Log   this session, newest last, showing %s\n' "${disk_fl_shown}"
  awk '{ count[$2]++ } END { printf "INFO %d   WARN %d   ERROR %d\n\n", count["INFO"], count["WARN"], count["ERROR"] }' "${DISK_APP_LOG}"
  disk_log_lines
  disk_fl_folder="$(disk_log_folder)"
  disk_fl_day="$(date -u +%Y-%m-%d)"
  printf '\n%s\n' "Kept in ${disk_fl_folder}/${disk_fl_day}.log when enban quits."
  printf '%s\n' "f filter   / search   s save as"
}

disk_log_lines() {
  disk_ll_room=$((DISK_APP_ROWS - 13))
  [ "${disk_ll_room}" -ge 3 ] || disk_ll_room=3
  disk_ll_text="$(DISK_APP_JOIN="${DISK_APP_L_SEARCH}" awk -v level="${DISK_APP_L_LEVEL}" '
    level == "warn" && $2 != "WARN" && $2 != "ERROR" { next }
    level == "error" && $2 != "ERROR" { next }
    ENVIRON["DISK_APP_JOIN"] != "" && index($0, ENVIRON["DISK_APP_JOIN"]) == 0 { next }
    { print }' "${DISK_APP_LOG}" | tail -n "${disk_ll_room}")"
  printf '%s\n' "${disk_ll_text:-Nothing matches.}"
}
