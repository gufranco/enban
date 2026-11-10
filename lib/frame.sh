#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_frame_repeat() {
  awk -v s="$1" -v n="$2" 'BEGIN { out = ""; for (i = 0; i < n; i++) out = out s; printf "%s", out }'
}

disk_frame_header() {
  disk_fh_name="$(disk_app_ink "${DISK_APP_C_ACCENT}" "${DISK_PROG}")"
  disk_fh_version="$(disk_version)"
  disk_fh_rest="$(disk_app_ink "${DISK_APP_C_MUTED}" "${disk_fh_version#* }  ${DISK_TAGLINE}")"
  printf ' %s %s\n' "${disk_fh_name}" "${disk_fh_rest}"
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
  disk_fb_inner=$((DISK_APP_COLS - 4))
  disk_fb_rule="$(disk_frame_repeat "$(printf '\342\224\200')" $((DISK_APP_COLS - 2)))"
  disk_app_ink "${DISK_APP_C_ACCENT}" "$(printf '\342\225\255%s\342\225\256' "${disk_fb_rule}")"
  printf '\n'
  while IFS= read -r disk_fb_line; do
    disk_fb_side="$(disk_app_ink "${DISK_APP_C_ACCENT}" "$(printf '\342\224\202')")"
    printf '%s %-*s %s\n' "${disk_fb_side}" "${disk_fb_inner}" "${disk_fb_line}" "${disk_fb_side}"
  done
  disk_app_ink "${DISK_APP_C_ACCENT}" "$(printf '\342\225\260%s\342\225\257' "${disk_fb_rule}")"
  printf '\n'
}

disk_frame_home() {
  printf '%s\n' "What would you like to do?" ""
  printf '%s\n' "  Write image to disc        ISO, BIN/CUE, CCD, MDS, NRG"
  printf '%s\n' "  Write files to disc        data, DVD Video, Blu-ray"
  printf '%s\n' "  Read disc to image         ISO, BIN/CUE, CCD, MDS"
  printf '%s\n' "  Build image from files     ISO9660, Joliet, UDF"
  printf '%s\n' "  Verify disc                alone or against an image"
  printf '%s\n' "  Discovery test             stress the drive and media"
  printf '%s\n' "" "These jobs arrive in the coming releases."
}

disk_frame_keys() {
  printf '%s\n' "Keys" ""
  printf '%s\n' "  0-9         switch to that tab"
  printf '%s\n' "  left/right  previous or next tab"
  printf '%s\n' "  q           quit and restore the terminal"
}

disk_frame_pane() {
  disk_fp_name="$(disk_app_tab_name "${DISK_APP_TAB}")"
  case "${disk_fp_name}" in
  Home) disk_frame_home ;;
  *) disk_frame_keys ;;
  esac
}

disk_frame_draw() {
  printf '\033[H\033[2J'
  disk_frame_header
  disk_frame_tabs
  disk_frame_pane | disk_frame_box
  disk_app_ink "${DISK_APP_C_MUTED}" " 0-9 tab   left/right move   q quit"
  printf '\n'
  DISK_APP_FRAMES=$((DISK_APP_FRAMES + 1))
}
