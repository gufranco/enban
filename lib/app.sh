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
  [1-9]*' '[1-9]*)
    DISK_APP_ROWS="${disk_az_size% *}"
    DISK_APP_COLS="${disk_az_size#* }"
    ;;
  *)
    DISK_APP_ROWS=24
    DISK_APP_COLS=80
    ;;
  esac
  [ "${DISK_APP_COLS}" -ge 60 ] || DISK_APP_COLS=60
  DISK_APP_PANE_LEFT="${DISK_APP_COLS}"
  [ "${DISK_APP_COLS}" -lt "${DISK_APP_WIDE}" ] || DISK_APP_PANE_LEFT=$((DISK_APP_COLS * 3 / 5))
  DISK_APP_GRID=1
  [ "${DISK_APP_PANE_LEFT}" -lt 70 ] || DISK_APP_GRID=2
}

disk_app_drive() {
  disk_ad_status=3
  if [ -n "${DISK_DRIVE}" ]; then
    disk_ad_status=0
    disk_drive_read "${DISK_DRIVE}" 2>/dev/null || disk_ad_status="$?"
  fi
  disk_app_drive_note "${disk_ad_status}"
  DISK_APP_DISC="$(disk_frame_disc)"
}

disk_app_drive_note() {
  case "$1" in
  0)
    DISK_APP_DRIVE_NOTE=""
    disk_an_profile="$(disk_drive_short_profile)"
    disk_an_free="$(disk_drive_free_text)"
    DISK_APP_STATUS="${disk_an_profile} loaded, ${disk_an_free} free."
    ;;
  2)
    DISK_APP_DRIVE_NOTE="Reading a drive is not supported on macOS yet."
    DISK_APP_STATUS="${DISK_APP_DRIVE_NOTE}"
    ;;
  3)
    DISK_APP_DRIVE_NOTE="$(printf '%s\n' "No drive chosen." "Start enban with --drive DRIVE," "or set ENBAN_DRIVE.")"
    DISK_APP_STATUS="No drive chosen."
    ;;
  *)
    DISK_APP_DRIVE_NOTE="Unable to read the drive."
    DISK_APP_STATUS="Unable to read the drive ${DISK_DRIVE}."
    ;;
  esac
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
  case "${DISK_APP_JOB}:${disk_ak_hex}" in
  running:) DISK_APP_KEY=tick ;;
  *) disk_app_decode "${disk_ak_hex}" ;;
  esac
}

disk_app_decode() {
  case "$1" in
  '' | 04) DISK_APP_KEY=eof ;;
  0a | 0d) DISK_APP_KEY=enter ;;
  09) DISK_APP_KEY=tab ;;
  20) DISK_APP_KEY=space ;;
  3f) DISK_APP_KEY=help ;;
  61) DISK_APP_KEY=a ;;
  62) DISK_APP_KEY=b ;;
  63) DISK_APP_KEY=c ;;
  66) DISK_APP_KEY=f ;;
  6e) DISK_APP_KEY=n ;;
  72) DISK_APP_KEY=r ;;
  76) DISK_APP_KEY=v ;;
  77) DISK_APP_KEY=w ;;
  78) DISK_APP_KEY=x ;;
  1b)
    stty min 0 time 1 2>/dev/null
    disk_ak_rest="$(disk_app_byte 2)"
    stty min 1 time 0 2>/dev/null
    disk_app_escape "${disk_ak_rest}"
    ;;
  3[0-9]) DISK_APP_KEY="${1#3}" ;;
  71) DISK_APP_KEY=q ;;
  *) DISK_APP_KEY=other ;;
  esac
}

disk_app_ask() {
  stty echo icanon min 1 time 0 2>/dev/null
  printf '\033[H\033[2J\033[?25h'
  DISK_APP_ANSWER=""
  if disk_ui_prompts; then
    DISK_APP_ANSWER="$(disk_ui_input "$1" "$2")" || DISK_APP_ANSWER=""
  else
    printf '%s: ' "$1"
    IFS= read -r DISK_APP_ANSWER || DISK_APP_ANSWER=""
  fi
  printf '\033[?25l'
  stty -echo -icanon min 1 time 0 2>/dev/null
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
  if [ "${DISK_APP_HELP}" -eq 1 ]; then
    DISK_APP_HELP=0
    case "$1" in
    q | eof) return 1 ;;
    *) return 0 ;;
    esac
  fi
  case "$1" in
  q | eof)
    disk_app_may_quit
    return
    ;;
  [0-9]) [ "$1" -ge "$2" ] || DISK_APP_TAB="$1" ;;
  tab) DISK_APP_TAB=$(((DISK_APP_TAB + 1) % $2)) ;;
  help) DISK_APP_HELP=1 ;;
  tick) disk_job_poll ;;
  *) disk_app_pane_key "$1" ;;
  esac
  return 0
}

disk_app_may_quit() {
  [ "${DISK_APP_JOB}" = running ] || return 1
  DISK_APP_STATUS="A ${DISK_APP_JOB_KIND} is running. Press c to cancel it first."
}

disk_app_pane_key() {
  case "$(disk_app_tab_name "${DISK_APP_TAB}")" in
  Home) disk_app_home_key "$1" ;;
  Write) disk_write_tab_key "$1" ;;
  Read) disk_read_tab_key "$1" ;;
  Verify) disk_verify_tab_key "$1" ;;
  Build) disk_build_tab_key "$1" ;;
  *) return 0 ;;
  esac
}

disk_app_home_key() {
  case "$1" in
  up) [ "${DISK_APP_FOCUS}" -lt "${DISK_APP_GRID}" ] || DISK_APP_FOCUS=$((DISK_APP_FOCUS - DISK_APP_GRID)) ;;
  down) [ $((DISK_APP_FOCUS + DISK_APP_GRID)) -gt 5 ] || DISK_APP_FOCUS=$((DISK_APP_FOCUS + DISK_APP_GRID)) ;;
  left) [ "${DISK_APP_GRID}" -eq 1 ] || DISK_APP_FOCUS=$((DISK_APP_FOCUS - DISK_APP_FOCUS % 2)) ;;
  right) [ "${DISK_APP_GRID}" -eq 1 ] || DISK_APP_FOCUS=$((DISK_APP_FOCUS - DISK_APP_FOCUS % 2 + 1)) ;;
  enter) DISK_APP_TAB="$(disk_frame_tile "${DISK_APP_FOCUS}" 3)" ;;
  *) return 0 ;;
  esac
}

disk_app_run() {
  disk_app_colours
  disk_app_size
  disk_app_drive
  disk_build_tab_refresh
  disk_app_enter
  trap 'disk_app_leave; exit 130' INT
  trap 'disk_app_leave; exit 143' TERM
  disk_ar_count="$(disk_app_tab_count)"
  while [ "${DISK_APP_FRAMES}" -lt "${DISK_APP_FRAME_LIMIT}" ]; do
    disk_frame_draw
    disk_app_wait_mode
    disk_app_key
    disk_app_act "${DISK_APP_KEY}" "${disk_ar_count}" || break
  done
  disk_app_leave
  trap - INT TERM
  return 0
}

disk_app_wait_mode() {
  case "${DISK_APP_JOB}" in
  running) stty min 0 time 5 2>/dev/null ;;
  *) stty min 1 time 0 2>/dev/null ;;
  esac
}

disk_app_tab_name() {
  printf '%s\n' "${DISK_APP_TABS}" | awk -v i="$1" '{ print $(i + 1) }'
}

disk_app_tab_count() {
  printf '%s\n' "${DISK_APP_TABS}" | wc -w | tr -d '[:space:]'
}
