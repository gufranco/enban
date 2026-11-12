#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_settings_tab_items() {
  case "$1" in
  0) printf '%s\n' write_verify write_eject write_speed write_mode write_finalize write_opc ;;
  1) printf '%s\n' read_verify read_retries read_ignore read_cue read_ccd ;;
  2) printf '%s\n' build_fs ;;
  3) printf '%s\n' queue_wait ;;
  4) printf '%s\n' event_bell event_confirm event_clean ;;
  *) printf '%s\n' theme ;;
  esac
}

disk_settings_tab_count() {
  disk_settings_tab_items "$1" | wc -l | tr -d ' '
}

disk_settings_tab_current() {
  disk_settings_tab_items "${DISK_APP_S_PAGE}" | sed -n "$((DISK_APP_S_FIELD + 1))p"
}

disk_settings_tab_key() {
  disk_sk_last=$(($(disk_settings_tab_count "${DISK_APP_S_PAGE}") - 1))
  case "$1" in
  up) [ "${DISK_APP_S_FIELD}" -le 0 ] || DISK_APP_S_FIELD=$((DISK_APP_S_FIELD - 1)) ;;
  down) [ "${DISK_APP_S_FIELD}" -ge "${disk_sk_last}" ] || DISK_APP_S_FIELD=$((DISK_APP_S_FIELD + 1)) ;;
  left) disk_settings_tab_page -1 ;;
  right) disk_settings_tab_page 1 ;;
  space) disk_settings_tab_switch || return 0 ;;
  enter) disk_settings_tab_edit || return 0 ;;
  *) return 0 ;;
  esac
}

disk_settings_tab_page() {
  disk_sp_page=$((DISK_APP_S_PAGE + $1))
  [ "${disk_sp_page}" -ge 0 ] && [ "${disk_sp_page}" -le "${DISK_SETTINGS_LAST_PAGE}" ] || return 0
  DISK_APP_S_PAGE="${disk_sp_page}"
  DISK_APP_S_FIELD=0
}

disk_settings_tab_is_switch() {
  case "$1" in
  write_speed | write_mode | read_retries | build_fs | queue_wait | theme) return 1 ;;
  *) return 0 ;;
  esac
}

disk_settings_tab_switch() {
  disk_sx_key="$(disk_settings_tab_current)"
  disk_settings_tab_is_switch "${disk_sx_key}" || return 1
  disk_sx_value="$(disk_settings_get "${disk_sx_key}")"
  disk_sx_value="$(disk_job_flip "${disk_sx_value}")"
  disk_settings_set "${disk_sx_key}" "${disk_sx_value}"
  disk_settings_tab_saved
}

disk_settings_tab_edit() {
  disk_settings_tab_switch && return 0
  case "$(disk_settings_tab_current)" in
  write_speed) disk_settings_tab_speed ;;
  write_mode) disk_settings_tab_mode ;;
  read_retries) disk_settings_tab_retries ;;
  build_fs) DISK_BUILD_FS="$(disk_build_tab_next_fs "${DISK_BUILD_FS}")" ;;
  queue_wait) disk_settings_tab_wait ;;
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

disk_settings_tab_mode() {
  case "${DISK_WRITE_MODE}" in
  dao) DISK_WRITE_MODE=tao ;;
  *) DISK_WRITE_MODE=dao ;;
  esac
}

disk_settings_tab_retries() {
  disk_app_ask "Times read tries a sector again, 0 to 99" "3"
  case "${DISK_APP_ANSWER}" in
  [0-9] | [0-9][0-9]) DISK_READ_RETRIES="${DISK_APP_ANSWER}" ;;
  *)
    DISK_APP_STATUS="The retries must be a whole number from 0 to 99."
    return 1
    ;;
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
  disk_sw_text="$(disk_settings_lines)"
  printf '%s\n' "${disk_sw_text}" >"$1"
}

disk_settings_lines() {
  disk_sn_page=0
  while [ "${disk_sn_page}" -le "${DISK_SETTINGS_LAST_PAGE}" ]; do
    for disk_sn_key in $(disk_settings_tab_items "${disk_sn_page}"); do
      disk_settings_line "${disk_sn_key}"
    done
    disk_sn_page=$((disk_sn_page + 1))
  done
}

disk_settings_line() {
  case "$1" in
  write_speed) printf 'write_speed=%s\n' "${DISK_WRITE_SPEED:-auto}" ;;
  write_mode) printf 'write_mode=%s\n' "${DISK_WRITE_MODE}" ;;
  read_retries) printf 'read_retries=%s\n' "${DISK_READ_RETRIES}" ;;
  build_fs) printf 'build_fs=%s\n' "${DISK_BUILD_FS}" ;;
  queue_wait) printf 'queue_wait=%s\n' "${DISK_QUEUE_WAIT}" ;;
  theme)
    disk_sg_source="$(disk_settings_tab_theme_source)"
    [ -n "${disk_sg_source}" ] || printf 'theme=%s\n' "${DISK_THEME}"
    ;;
  *)
    disk_sg_value="$(disk_settings_get "$1")"
    disk_sg_word="$(disk_settings_word "${disk_sg_value}")"
    printf '%s=%s\n' "$1" "${disk_sg_word}"
    ;;
  esac
}

disk_settings_word() {
  case "$1" in
  y) printf 'yes\n' ;;
  *) printf 'no\n' ;;
  esac
}
