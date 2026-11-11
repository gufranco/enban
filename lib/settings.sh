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
  write_verify | write_eject | read_verify) disk_settings_switch "$@" ;;
  write_speed) disk_settings_speed "$@" ;;
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
  case "$2" in
  write_verify) DISK_WRITE_VERIFY="${disk_sw_value}" ;;
  write_eject) DISK_WRITE_EJECT="${disk_sw_value}" ;;
  *) DISK_READ_VERIFY="${disk_sw_value}" ;;
  esac
}

disk_settings_speed() {
  case "$3" in
  auto) DISK_WRITE_SPEED="" ;;
  '' | *[!0-9]*) disk_warning "settings line $1: write_speed must be auto or a whole number, got: $3" ;;
  *) DISK_WRITE_SPEED="$3" ;;
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
