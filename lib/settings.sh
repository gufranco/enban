#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_settings_file() {
  printf '%s/settings\n' "${DISK_CONFIG}"
}

disk_settings_load() {
  disk_sl_file="$(disk_settings_file)"
  [ -f "${disk_sl_file}" ] || return 0
  disk_sl_line=0
  while IFS= read -r disk_sl_text || [ -n "${disk_sl_text}" ]; do
    disk_sl_line=$((disk_sl_line + 1))
    case "${disk_sl_text}" in
    '' | '#'*) continue ;;
    *) disk_settings_apply "${disk_sl_line}" "${disk_sl_text%%=*}" "${disk_sl_text#*=}" ;;
    esac
  done <"${disk_sl_file}"
}

disk_settings_apply() {
  case "$2" in
  write_verify | write_eject | write_finalize | write_opc) disk_settings_switch "$@" ;;
  read_verify | read_ignore | read_cue | read_ccd) disk_settings_switch "$@" ;;
  event_bell | event_confirm | event_clean) disk_settings_switch "$@" ;;
  write_speed) disk_settings_speed "$@" ;;
  write_mode) disk_settings_mode "$@" ;;
  read_retries) disk_settings_retries "$@" ;;
  build_fs) disk_settings_fs "$@" ;;
  queue_wait) disk_settings_wait "$@" ;;
  theme) disk_settings_theme "$3" ;;
  *) disk_warning "settings line $1: unknown setting $2." ;;
  esac
}

disk_settings_switch() {
  case "$3" in
  yes) disk_sw_value=y ;;
  no) disk_sw_value=n ;;
  *)
    disk_warning "settings line $1: $2 must be yes or no, got: $3"
    return 0
    ;;
  esac
  disk_settings_set "$2" "${disk_sw_value}"
}

disk_settings_set() {
  case "$1" in
  write_verify) DISK_WRITE_VERIFY="$2" ;;
  write_eject) DISK_WRITE_EJECT="$2" ;;
  write_finalize) DISK_WRITE_FINALIZE="$2" ;;
  write_opc) DISK_WRITE_OPC="$2" ;;
  read_verify) DISK_READ_VERIFY="$2" ;;
  read_ignore) DISK_READ_IGNORE="$2" ;;
  read_cue) DISK_READ_CUE="$2" ;;
  read_ccd) DISK_READ_CCD="$2" ;;
  event_bell) DISK_EVENT_BELL="$2" ;;
  event_confirm) DISK_EVENT_CONFIRM="$2" ;;
  *) DISK_EVENT_CLEAN="$2" ;;
  esac
}

disk_settings_get() {
  case "$1" in
  write_verify) printf '%s\n' "${DISK_WRITE_VERIFY}" ;;
  write_eject) printf '%s\n' "${DISK_WRITE_EJECT}" ;;
  write_finalize) printf '%s\n' "${DISK_WRITE_FINALIZE}" ;;
  write_opc) printf '%s\n' "${DISK_WRITE_OPC}" ;;
  read_verify) printf '%s\n' "${DISK_READ_VERIFY}" ;;
  read_ignore) printf '%s\n' "${DISK_READ_IGNORE}" ;;
  read_cue) printf '%s\n' "${DISK_READ_CUE}" ;;
  read_ccd) printf '%s\n' "${DISK_READ_CCD}" ;;
  event_bell) printf '%s\n' "${DISK_EVENT_BELL}" ;;
  event_confirm) printf '%s\n' "${DISK_EVENT_CONFIRM}" ;;
  *) printf '%s\n' "${DISK_EVENT_CLEAN}" ;;
  esac
}

disk_settings_speed() {
  case "$3" in
  auto) DISK_WRITE_SPEED="" ;;
  '' | *[!0-9]*) disk_warning "settings line $1: write_speed must be auto or a whole number, got: $3" ;;
  *) DISK_WRITE_SPEED="$3" ;;
  esac
}

disk_settings_mode() {
  case "$3" in
  dao | tao) DISK_WRITE_MODE="$3" ;;
  *) disk_warning "settings line $1: write_mode must be dao or tao, got: $3" ;;
  esac
}

disk_settings_retries() {
  case "$3" in
  [0-9] | [0-9][0-9]) DISK_READ_RETRIES="$3" ;;
  *) disk_warning "settings line $1: read_retries must be a whole number from 0 to 99, got: $3" ;;
  esac
}

disk_settings_fs() {
  disk_sf_problem="$(disk_build_fs "$3" 2>&1)" || disk_sf_problem="bad"
  if [ -n "${disk_sf_problem}" ]; then
    disk_warning "settings line $1: build_fs takes iso9660, joliet and udf with iso9660 among them, got: $3"
    return 0
  fi
  DISK_BUILD_FS="$3"
}

disk_settings_wait() {
  [ -z "${ENBAN_QUEUE_WAIT:-}" ] || return 0
  case "$3" in
  '' | *[!0-9]*) disk_warning "settings line $1: queue_wait must be a whole number of seconds, got: $3" ;;
  *) DISK_QUEUE_WAIT="$3" ;;
  esac
}

disk_settings_theme() {
  [ -z "${ENBAN_THEME:-}${KODOUGU_THEME:-}" ] || return 0
  DISK_THEME="$1"
}
