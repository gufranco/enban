#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_settings_view_pages() {
  disk_sv_page=0
  disk_sv_bar=""
  for disk_sv_name in Write Read Build Queue Events Look; do
    disk_sv_cell=" ${disk_sv_name} "
    [ "${disk_sv_page}" -ne "${DISK_APP_S_PAGE}" ] || disk_sv_cell="[${disk_sv_name}]"
    disk_sv_bar="${disk_sv_bar}${disk_sv_cell} "
    disk_sv_page=$((disk_sv_page + 1))
  done
  printf '%s\n' "${disk_sv_bar% }"
}

disk_settings_view_label() {
  case "$1" in
  write_verify | read_verify) printf 'Verify\n' ;;
  write_eject) printf 'Eject\n' ;;
  write_speed) printf 'Speed\n' ;;
  write_mode) printf 'Mode\n' ;;
  write_finalize) printf 'Finalize\n' ;;
  write_opc) printf 'OPC\n' ;;
  read_retries) printf 'Retries\n' ;;
  read_ignore) printf 'Skip bad\n' ;;
  read_cue) printf 'CUE sheet\n' ;;
  read_ccd) printf 'CloneCD\n' ;;
  build_fs) printf 'Type\n' ;;
  queue_wait) printf 'Wait\n' ;;
  event_bell) printf 'Bell\n' ;;
  event_confirm) printf 'Ask first\n' ;;
  event_clean) printf 'Clean up\n' ;;
  *) printf 'Theme\n' ;;
  esac
}

disk_settings_view_value() {
  case "$1" in
  write_speed) disk_settings_view_speed ;;
  write_mode) disk_settings_view_mode ;;
  read_retries) printf '%s\n' "${DISK_READ_RETRIES}" ;;
  build_fs) disk_build_fs_names "${DISK_BUILD_FS}" ;;
  queue_wait) printf '%s seconds\n' "${DISK_QUEUE_WAIT}" ;;
  theme) disk_settings_view_theme ;;
  *)
    disk_sa_value="$(disk_settings_get "$1")"
    disk_job_box "${disk_sa_value}"
    printf '\n'
    ;;
  esac
}

disk_settings_view_speed() {
  if [ -z "${DISK_WRITE_SPEED}" ]; then
    printf 'chosen by the drive\n'
    return 0
  fi
  printf '%sx\n' "${DISK_WRITE_SPEED}"
}

disk_settings_view_mode() {
  case "${DISK_WRITE_MODE}" in
  tao) printf 'track at once\n' ;;
  *) printf 'disc at once\n' ;;
  esac
}

disk_settings_view_theme() {
  disk_sm_source="$(disk_settings_tab_theme_source)"
  if [ -n "${disk_sm_source}" ]; then
    printf '%s, from %s\n' "${DISK_THEME}" "${disk_sm_source}"
    return 0
  fi
  printf '%s\n' "${DISK_THEME}"
}

disk_settings_view_hint() {
  case "$1" in
  write_verify) printf 'Compare the disc with the image after each write.\n' ;;
  write_eject) printf 'Open the tray once a write is done.\n' ;;
  write_speed) printf 'The speed a write asks the drive for.\n' ;;
  write_mode) printf 'Disc at once writes in one pass; track at once writes each track on its own.\n' ;;
  write_finalize) printf 'Close the disc so nothing more can be added to it.\n' ;;
  write_opc) printf 'Calibrate the laser power on the disc before each write.\n' ;;
  read_verify) printf 'Compare the image with the disc after each read.\n' ;;
  read_retries) printf 'How many times a read tries again after an error.\n' ;;
  read_ignore) printf 'Write zeros for sectors that will not read instead of stopping.\n' ;;
  read_cue) printf 'Write a CUE sheet beside each image read.\n' ;;
  read_ccd) printf 'Read a CD raw into an .img with its CloneCD .sub and .ccd files.\n' ;;
  build_fs) printf 'The file systems a build writes.\n' ;;
  queue_wait) printf 'How long the queue waits for the next blank disc.\n' ;;
  event_bell) printf 'Ring the terminal bell when a job ends.\n' ;;
  event_confirm) printf 'Ask before c cancels a running job.\n' ;;
  event_clean) printf 'Delete what a cancelled or failed job left half written.\n' ;;
  *) printf 'The colours of the app.\n' ;;
  esac
}

disk_frame_settings() {
  disk_fz_pages="$(disk_settings_view_pages)"
  printf '%s\n' "Settings" "" "${disk_fz_pages}" ""
  disk_fz_row=0
  for disk_fz_key in $(disk_settings_tab_items "${DISK_APP_S_PAGE}"); do
    disk_fz_label="$(disk_settings_view_label "${disk_fz_key}")"
    disk_fz_value="$(disk_settings_view_value "${disk_fz_key}")"
    disk_job_row "${disk_fz_row}" "${DISK_APP_S_FIELD}" "${disk_fz_label}" "${disk_fz_value}"
    disk_fz_row=$((disk_fz_row + 1))
  done
  disk_fz_current="$(disk_settings_tab_current)"
  disk_fz_hint="$(disk_settings_view_hint "${disk_fz_current}")"
  disk_fz_file="$(disk_settings_file)"
  printf '%s\n' "" "${disk_fz_hint}" "" "Saved to" "  ${disk_fz_file}" "" "left right page   space toggle   enter edit"
}
