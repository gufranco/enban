#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_frame_repeat() {
  awk -v s="$1" -v n="$2" 'BEGIN { out = ""; for (i = 0; i < n; i++) out = out s; printf "%s", out }'
}

disk_frame_header() {
  disk_fh_version="$(disk_version)"
  disk_fh_left=" ${DISK_PROG} ${disk_fh_version#* }  ${DISK_TAGLINE}"
  disk_fh_name="$(disk_app_ink "${DISK_APP_C_ACCENT}" "${DISK_PROG}")"
  disk_fh_rest="$(disk_app_ink "${DISK_APP_C_MUTED}" "${disk_fh_version#* }  ${DISK_TAGLINE}")"
  disk_fh_badge="$(disk_frame_badge)"
  disk_fh_gap=$((DISK_APP_COLS - ${#disk_fh_left} - ${#disk_fh_badge} - 1))
  if [ -z "${disk_fh_badge}" ] || [ "${disk_fh_gap}" -lt 2 ]; then
    printf ' %s %s\n' "${disk_fh_name}" "${disk_fh_rest}"
    return 0
  fi
  disk_fh_pad="$(disk_frame_repeat ' ' "${disk_fh_gap}")"
  disk_fh_ink="$(disk_app_ink "${DISK_APP_C_ACCENT}" "${disk_fh_badge}")"
  printf ' %s %s%s%s\n' "${disk_fh_name}" "${disk_fh_rest}" "${disk_fh_pad}" "${disk_fh_ink}"
}

disk_frame_badge() {
  [ -n "${DISK_APP_DRIVE_NOTE}" ] && return 0
  disk_fg_profile="$(disk_drive_short_profile)"
  printf 'drive %s  %s' "${DISK_DRIVE}" "${disk_fg_profile}"
}

disk_frame_tabs() {
  disk_ft_line=" "
  disk_ft_index=0
  for disk_ft_name in ${DISK_APP_TABS}; do
    if [ "${disk_ft_index}" -eq "${DISK_APP_TAB}" ]; then
      disk_ft_line="${disk_ft_line}$(disk_app_pill "${disk_ft_index} ${disk_ft_name}")"
    else
      disk_ft_line="${disk_ft_line} $(disk_app_ink "${DISK_APP_C_MUTED}" "${disk_ft_index} ${disk_ft_name}") "
    fi
    disk_ft_index=$((disk_ft_index + 1))
  done
  printf '%s\n' "${disk_ft_line}"
}

disk_frame_box() {
  disk_fb_rule="$(disk_frame_repeat "$(printf '\342\224\200')" $(($1 - 2)))"
  disk_fb_top="$(disk_app_ink "${DISK_APP_C_ACCENT}" "$(printf '\342\225\255%s\342\225\256' "${disk_fb_rule}")")"
  disk_fb_bottom="$(disk_app_ink "${DISK_APP_C_ACCENT}" "$(printf '\342\225\260%s\342\225\257' "${disk_fb_rule}")")"
  disk_fb_side="$(disk_app_ink "${DISK_APP_C_ACCENT}" "$(printf '\342\224\202')")"
  disk_frame_wrap $(($1 - 4)) | awk -v w=$(($1 - 4)) -v top="${disk_fb_top}" -v bottom="${disk_fb_bottom}" -v side="${disk_fb_side}" '
    BEGIN { print top }
    { printf "%s %s %s\n", side, sprintf("%-" w "s", $0), side }
    END { print bottom }'
}

disk_frame_wrap() {
  awk -v w="$1" '
    {
      line = $0
      while (length(line) > w) {
        cut = w
        while (cut > 1 && substr(line, cut + 1, 1) != " ") cut--
        if (cut == 1) cut = w
        print substr(line, 1, cut)
        line = substr(line, cut + 1)
        sub(/^ +/, "", line)
      }
      print line
    }'
}

disk_frame_tiles() {
  printf '%s\n' \
    "Write image to disc|ISO, BIN/CUE, CCD, MDS, NRG|1" \
    "Write files to disc|Data, DVD Video, Blu-ray|1" \
    "Read disc to image|ISO, BIN/CUE, CCD, MDS|2" \
    "Build image from files|ISO9660, Joliet, UDF|3" \
    "Verify disc|Alone or against an image|4" \
    "Discovery test|Stress the drive and media|5"
}

disk_frame_tile() {
  disk_frame_tiles | awk -F '|' -v i="$1" -v f="$2" 'NR == i + 1 { print $f }'
}

disk_frame_home() {
  printf '%s\n' "What would you like to do?" ""
  disk_fo_cell=$(((DISK_APP_PANE_LEFT - 6) / 2))
  disk_frame_tiles | awk -F '|' -v focus="${DISK_APP_FOCUS}" -v grid="${DISK_APP_GRID}" -v cell="${disk_fo_cell}" '
    function cut(s, n) { return substr(sprintf("%-" n "s", s), 1, n) }
    { title[NR - 1] = $1; detail[NR - 1] = $2 }
    END {
      for (i = 0; i < 6; i++) mark[i] = (i == focus ? "> " : "  ")
      if (grid == 1) {
        for (i = 0; i < 6; i++) print mark[i] cut(title[i], 23) " " detail[i]
        exit
      }
      for (r = 0; r < 6; r += 2) {
        print cut(mark[r] title[r], cell) "  " cut(mark[r + 1] title[r + 1], cell)
        print cut("  " detail[r], cell) "  " cut("  " detail[r + 1], cell)
        print ""
      }
    }'
}

disk_frame_later() {
  disk_fl_title="$(disk_frame_tile 5 1)"
  printf '%s\n' "$1" "" "${disk_fl_title} arrives in a coming release."
}

disk_frame_soon() {
  printf '%s\n' "$1" "" "This tab arrives in a coming release."
}

disk_frame_keys() {
  printf '%s\n' "Keys" ""
  printf '%s\n' "  arrows      move between the jobs on Home"
  printf '%s\n' "  enter       open the job, or edit the field"
  printf '%s\n' "  space       turn the field on or off"
  printf '%s\n' "  w           write, on Write"
  printf '%s\n' "  r           read, on Read"
  printf '%s\n' "  v           verify, on Verify"
  printf '%s\n' "  a f x n b   add a file or folder, remove, rename, build, on Build"
  printf '%s\n' "  c           cancel the running job"
  printf '%s\n' "  esc         back to the tool list, on Tools"
  printf '%s\n' "  tab         next tab"
  printf '%s\n' "  0-9         jump to that tab"
  printf '%s\n' "  ?           these keys, closed by the next key"
  printf '%s\n' "  q           quit and restore the terminal"
}

disk_frame_left() {
  if [ "${DISK_APP_HELP}" -eq 1 ]; then
    disk_frame_keys
    return 0
  fi
  disk_fp_name="$(disk_app_tab_name "${DISK_APP_TAB}")"
  case "${disk_fp_name}" in
  Home) disk_frame_home ;;
  Write) disk_frame_write ;;
  Read) disk_frame_read ;;
  Verify) disk_frame_verify ;;
  Build) disk_frame_build ;;
  Tools) disk_frame_tools ;;
  Discovery) disk_frame_later "${disk_fp_name}" ;;
  *) disk_frame_soon "${disk_fp_name}" ;;
  esac
}

disk_frame_disc() {
  printf '%s\n' "Disc"
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    printf '%s\n' "${DISK_APP_DRIVE_NOTE}"
    return 0
  fi
  disk_fd_free="$(disk_drive_free_text)"
  disk_fd_speeds="$(disk_drive_speed_text)"
  printf 'Profile      %s\n' "${DISK_DRIVE_PROFILE}"
  printf 'Status       %s\n' "${DISK_DRIVE_STATUS}"
  printf 'Sessions     %s, %s data sectors\n' "${DISK_DRIVE_SESSIONS}" "${DISK_DRIVE_DATA}"
  printf 'Free         %s sectors, %s\n' "${DISK_DRIVE_FREE}" "${disk_fd_free}"
  printf 'Speeds       %s\n' "${disk_fd_speeds}"
  printf '%s\n' "" "Drive"
  printf 'Device       %s\n' "${DISK_DRIVE}"
  printf 'Model        %s %s\n' "${DISK_DRIVE_VENDOR}" "${DISK_DRIVE_PRODUCT}"
  printf 'Firmware     %s\n' "${DISK_DRIVE_REVISION}"
}

disk_frame_panes() {
  disk_fs_left="$(disk_frame_left)"
  disk_fs_name="$(disk_app_tab_name "${DISK_APP_TAB}")"
  disk_fs_right="${DISK_APP_DISC}"
  [ "${disk_fs_name}" != Build ] || disk_fs_right="${DISK_APP_B_SIDE}"
  disk_fs_room=$((DISK_APP_ROWS - 6))
  [ "${disk_fs_room}" -ge 3 ] || disk_fs_room=3
  if [ "${DISK_APP_COLS}" -lt "${DISK_APP_WIDE}" ]; then
    disk_frame_stacked "${disk_fs_room}"
    return 0
  fi
  disk_frame_beside "${disk_fs_room}"
}

disk_frame_stacked() {
  disk_fk_right="$(printf '%s\n' "${disk_fs_right}" | disk_frame_wrap $((DISK_APP_COLS - 4)) | disk_frame_clip $(($1 / 2)))"
  disk_fk_lines="$(printf '%s\n' "${disk_fk_right}" | awk 'END { print NR }')"
  disk_fk_room=$(($1 - disk_fk_lines - 2))
  [ "${disk_fk_room}" -ge 3 ] || disk_fk_room=3
  printf '%s\n' "${disk_fs_left}" | disk_frame_wrap $((DISK_APP_COLS - 4)) | disk_frame_clip "${disk_fk_room}" | disk_frame_box "${DISK_APP_COLS}"
  printf '%s\n' "${disk_fk_right}" | disk_frame_box "${DISK_APP_COLS}"
}

disk_frame_beside() {
  disk_fs_rwidth=$((DISK_APP_COLS - DISK_APP_PANE_LEFT - 1))
  disk_fs_left="$(printf '%s\n' "${disk_fs_left}" | disk_frame_wrap $((DISK_APP_PANE_LEFT - 4)) | disk_frame_clip "$1")"
  disk_fs_right="$(printf '%s\n' "${disk_fs_right}" | disk_frame_wrap $((disk_fs_rwidth - 4)) | disk_frame_clip "$1")"
  disk_fs_lines="$(printf '%s\n' "${disk_fs_left}" | awk 'END { print NR }')"
  disk_fs_height="$(printf '%s\n' "${disk_fs_right}" | awk -v n="${disk_fs_lines}" 'END { print (NR > n ? NR : n) }')"
  disk_fs_lbox="$(disk_frame_padded "${disk_fs_left}" "${disk_fs_height}" | disk_frame_box "${DISK_APP_PANE_LEFT}")"
  disk_fs_rbox="$(disk_frame_padded "${disk_fs_right}" "${disk_fs_height}" | disk_frame_box "${disk_fs_rwidth}")"
  disk_frame_join "${disk_fs_lbox}" "${disk_fs_rbox}"
}

disk_frame_clip() {
  awk -v room="$1" '
    { line[NR] = $0; if (focus == "" && $0 ~ /^> /) focus = NR }
    END {
      if (NR <= room) { for (i = 1; i <= NR; i++) print line[i]; exit }
      print line[1]
      rest = room - 1
      first = (focus == "" ? 2 : focus - int(rest / 2))
      if (first > NR - rest + 1) first = NR - rest + 1
      if (first < 2) first = 2
      for (i = first; i < first + rest; i++) print line[i]
    }'
}

disk_frame_padded() {
  printf '%s\n' "$1" | awk -v n="$2" '{ print } END { for (i = NR; i < n; i++) print "" }'
}

disk_frame_join() {
  printf '%s\n' "$1" | DISK_APP_JOIN="$2" awk 'BEGIN { split(ENVIRON["DISK_APP_JOIN"], right, "\n") } { print $0 " " right[NR] }'
}

disk_frame_draw() {
  printf '\033[H\033[2J'
  disk_frame_header
  disk_frame_tabs
  disk_frame_panes
  disk_app_ink "${DISK_APP_C_TEXT}" " ${DISK_APP_STATUS}"
  printf '\n'
  disk_app_ink "${DISK_APP_C_MUTED}" " arrows move   enter open   tab next tab   0-9 jump to tab   ? keys   q quit"
  printf '\n'
  DISK_APP_FRAMES=$((DISK_APP_FRAMES + 1))
}
