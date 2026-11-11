#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_settings_tab_key() {
  case "$1" in
  up) [ "${DISK_APP_S_FIELD}" -le 0 ] || DISK_APP_S_FIELD=$((DISK_APP_S_FIELD - 1)) ;;
  down) [ "${DISK_APP_S_FIELD}" -ge 6 ] || DISK_APP_S_FIELD=$((DISK_APP_S_FIELD + 1)) ;;
  space) disk_settings_tab_switch || return 0 ;;
  enter) disk_settings_tab_edit || return 0 ;;
  *) return 0 ;;
  esac
}

disk_settings_tab_switch() {
  case "${DISK_APP_S_FIELD}" in
  0) DISK_WRITE_VERIFY="$(disk_job_flip "${DISK_WRITE_VERIFY}")" ;;
  1) DISK_WRITE_EJECT="$(disk_job_flip "${DISK_WRITE_EJECT}")" ;;
  3) DISK_READ_VERIFY="$(disk_job_flip "${DISK_READ_VERIFY}")" ;;
  *) return 1 ;;
  esac
  disk_settings_tab_saved
}

disk_settings_tab_edit() {
  disk_settings_tab_switch && return 0
  case "${DISK_APP_S_FIELD}" in
  2) disk_settings_tab_speed ;;
  4) DISK_BUILD_FS="$(disk_build_tab_next_fs "${DISK_BUILD_FS}")" ;;
  5) disk_settings_tab_wait ;;
  *) disk_settings_tab_theme ;;
  esac || return 1
  disk_settings_tab_saved
}

disk_settings_tab_speed() {
  disk_app_ask "Default write speed, empty for the drive's choice" "8"
  case "${DISK_APP_ANSWER}" in
  *[!0-9]*)
    DISK_APP_STATUS="The speed must be a whole number, such as 8."
    return 1
    ;;
  *) DISK_WRITE_SPEED="${DISK_APP_ANSWER}" ;;
  esac
}

disk_settings_tab_wait() {
  disk_app_ask "Seconds the queue waits for a blank disc" "600"
  case "${DISK_APP_ANSWER}" in
  '' | *[!0-9]*)
    DISK_APP_STATUS="The wait must be a whole number of seconds."
    return 1
    ;;
  *) DISK_QUEUE_WAIT="${DISK_APP_ANSWER}" ;;
  esac
}

disk_settings_tab_theme() {
  disk_st_source="$(disk_settings_tab_theme_source)"
  if [ -n "${disk_st_source}" ]; then
    DISK_APP_STATUS="${disk_st_source} sets the theme. Unset it to choose one here."
    return 1
  fi
  disk_app_ask "Theme: ${DISK_UI_THEMES}" "${DISK_THEME}"
  if ! (disk_ui_palette "${DISK_APP_ANSWER}"); then
    DISK_APP_STATUS="There is no theme named ${DISK_APP_ANSWER}."
    return 1
  fi
  DISK_THEME="${DISK_APP_ANSWER}"
  disk_ui_setup || :
  disk_app_colours
}

disk_settings_tab_theme_source() {
  if [ -n "${ENBAN_THEME:-}" ]; then
    printf 'ENBAN_THEME\n'
    return 0
  fi
  [ -z "${KODOUGU_THEME:-}" ] || printf 'KODOUGU_THEME\n'
}

disk_settings_tab_saved() {
  disk_app_defaults
  disk_ss_file="$(disk_settings_file)"
  if disk_settings_write "${disk_ss_file}" 2>/dev/null; then
    DISK_APP_STATUS="Saved. Changes apply to the next job."
    return 0
  fi
  DISK_APP_STATUS="Unable to save the settings to ${disk_ss_file}."
}

disk_settings_write() {
  mkdir -p "${DISK_CONFIG}" || return 1
  disk_sw_theme="$(disk_settings_tab_theme_source)"
  disk_sw_verify="$(disk_settings_word "${DISK_WRITE_VERIFY}")"
  disk_sw_eject="$(disk_settings_word "${DISK_WRITE_EJECT}")"
  disk_sw_read="$(disk_settings_word "${DISK_READ_VERIFY}")"
  printf 'write_verify=%s\nwrite_eject=%s\n' "${disk_sw_verify}" "${disk_sw_eject}" >"$1"
  printf 'write_speed=%s\nread_verify=%s\n' "${DISK_WRITE_SPEED:-auto}" "${disk_sw_read}" >>"$1"
  printf 'build_fs=%s\nqueue_wait=%s\n' "${DISK_BUILD_FS}" "${DISK_QUEUE_WAIT}" >>"$1"
  [ -n "${disk_sw_theme}" ] || printf 'theme=%s\n' "${DISK_THEME}" >>"$1"
}

disk_settings_word() {
  case "$1" in
  y) printf 'yes\n' ;;
  *) printf 'no\n' ;;
  esac
}

disk_frame_settings() {
  disk_fz_speed="chosen by the drive"
  [ -z "${DISK_WRITE_SPEED}" ] || disk_fz_speed="${DISK_WRITE_SPEED}x"
  disk_fz_fs="$(disk_build_fs_names "${DISK_BUILD_FS}")"
  disk_fz_source="$(disk_settings_tab_theme_source)"
  disk_fz_theme="${DISK_THEME}"
  [ -z "${disk_fz_source}" ] || disk_fz_theme="${DISK_THEME}, from ${disk_fz_source}"
  printf '%s\n' "Settings" "" "Write"
  disk_settings_switch_row 0 Verify "${DISK_WRITE_VERIFY}"
  disk_settings_switch_row 1 Eject "${DISK_WRITE_EJECT}"
  disk_settings_row 2 Speed "${disk_fz_speed}"
  printf '%s\n' "" "Read"
  disk_settings_switch_row 3 Verify "${DISK_READ_VERIFY}"
  printf '%s\n' "" "Build"
  disk_settings_row 4 Type "${disk_fz_fs}"
  printf '%s\n' "" "Queue"
  disk_settings_row 5 Wait "${DISK_QUEUE_WAIT} seconds"
  printf '%s\n' "" "Look"
  disk_settings_row 6 Theme "${disk_fz_theme}"
  disk_fz_file="$(disk_settings_file)"
  printf '%s\n' "" "Saved to" "  ${disk_fz_file}" "" "space toggle   enter edit"
}

disk_settings_switch_row() {
  disk_sr_box="$(disk_job_box "$3")"
  disk_settings_row "$1" "$2" "${disk_sr_box}"
}

disk_settings_row() {
  disk_job_row "$1" "${DISK_APP_S_FIELD}" "$2" "$3"
}
