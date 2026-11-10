#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_app_rgb() {
  printf '%s\n' "$1" | awk '{
    hex = "0123456789abcdef"; s = tolower(substr($0, 2)); out = ""
    for (i = 0; i < 3; i++) {
      v = (index(hex, substr(s, i * 2 + 1, 1)) - 1) * 16 + index(hex, substr(s, i * 2 + 2, 1)) - 1
      out = out (i ? ";" : "") v
    }
    print out
  }'
}

disk_app_colours() {
  DISK_APP_C_ACCENT=""
  DISK_APP_C_MUTED=""
  DISK_APP_C_TEXT=""
  [ -n "${DISK_UI_ACCENT}" ] || return 0
  DISK_APP_C_ACCENT="$(disk_app_rgb "${DISK_UI_ACCENT}")"
  DISK_APP_C_MUTED="$(disk_app_rgb "${DISK_UI_MUTED}")"
  DISK_APP_C_TEXT="$(disk_app_rgb "${DISK_UI_TEXT}")"
}

disk_app_ink() {
  if [ -z "$1" ]; then
    printf '%s' "$2"
    return 0
  fi
  printf '\033[38;2;%sm%s\033[0m' "$1" "$2"
}

disk_app_pill() {
  if [ -z "${DISK_APP_C_ACCENT}" ]; then
    printf '[%s]' "$1"
    return 0
  fi
  printf '\033[1;38;2;30;30;46;48;2;%sm %s \033[0m' "${DISK_APP_C_ACCENT}" "$1"
}

disk_app_size() {
  disk_az_size="$(stty size 2>/dev/null)" || disk_az_size=""
  case "${disk_az_size}" in
  [0-9]*' '[0-9]*) ;;
  *) disk_az_size="24 80" ;;
  esac
  DISK_APP_ROWS="${disk_az_size% *}"
  DISK_APP_COLS="${disk_az_size#* }"
  [ "${DISK_APP_COLS}" -ge 60 ] || DISK_APP_COLS=60
}

disk_app_enter() {
  stty -echo -icanon min 1 time 0
  DISK_APP_STTY=changed
  printf '\033[?1049h\033[?25l'
}

disk_app_leave() {
  printf '\033[?25h\033[?1049l'
  [ -n "${DISK_APP_STTY}" ] || return 0
  DISK_APP_STTY=""
  stty echo icanon 2>/dev/null
  disk_app_echo_on && return 0
  disk_warning "the terminal still hides what you type. run stty sane to restore it."
  return 1
}

disk_app_echo_on() {
  stty -a 2>/dev/null | tr -s ' ;' '\n' | grep -qx echo
}

disk_app_byte() {
  dd bs=1 count="$1" 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

disk_app_key() {
  disk_ak_hex="$(disk_app_byte 1)"
  case "${disk_ak_hex}" in
  '' | 04) DISK_APP_KEY=eof ;;
  0a | 0d) DISK_APP_KEY=enter ;;
  1b)
    stty min 0 time 1 2>/dev/null
    disk_ak_rest="$(disk_app_byte 2)"
    stty min 1 time 0 2>/dev/null
    disk_app_escape "${disk_ak_rest}"
    ;;
  3[0-9]) DISK_APP_KEY="${disk_ak_hex#3}" ;;
  71) DISK_APP_KEY=q ;;
  *) DISK_APP_KEY=other ;;
  esac
}

disk_app_escape() {
  case "$1" in
  5b41) DISK_APP_KEY=up ;;
  5b42) DISK_APP_KEY=down ;;
  5b43) DISK_APP_KEY=right ;;
  5b44) DISK_APP_KEY=left ;;
  *) DISK_APP_KEY=esc ;;
  esac
}

disk_app_act() {
  case "$1" in
  q | eof) return 1 ;;
  [0-9]) [ "$1" -ge "$2" ] || DISK_APP_TAB="$1" ;;
  right) DISK_APP_TAB=$(((DISK_APP_TAB + 1) % $2)) ;;
  left) DISK_APP_TAB=$(((DISK_APP_TAB + $2 - 1) % $2)) ;;
  *) ;;
  esac
  return 0
}

disk_app_run() {
  disk_app_colours
  disk_app_size
  disk_app_enter
  trap 'disk_app_leave; exit 130' INT
  trap 'disk_app_leave; exit 143' TERM
  disk_ar_count="$(disk_app_tab_count)"
  while [ "${DISK_APP_FRAMES}" -lt "${DISK_APP_FRAME_LIMIT}" ]; do
    disk_frame_draw
    disk_app_key
    disk_app_act "${DISK_APP_KEY}" "${disk_ar_count}" || break
  done
  disk_app_leave
  trap - INT TERM
  return 0
}

disk_app_tab_name() {
  printf '%s\n' "${DISK_APP_TABS}" | awk -v i="$1" '{ print $(i + 1) }'
}

disk_app_tab_count() {
  printf '%s\n' "${DISK_APP_TABS}" | wc -w | tr -d '[:space:]'
}
