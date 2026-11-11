#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_tools_tab_label() {
  disk_app_ask "ISO image to relabel" "path to an .iso file"
  disk_tl_image="${DISK_APP_ANSWER}"
  [ -n "${disk_tl_image}" ] || return 0
  disk_app_ask "New label" "up to 32 characters"
  [ -n "${DISK_APP_ANSWER}" ] || return 0
  DISK_LABEL_IMAGE="${disk_tl_image}"
  DISK_LABEL_NAME="${DISK_APP_ANSWER}"
  disk_drive_tools_say disk_label_run || :
}

disk_tools_tab_layer() {
  disk_app_ask "Image to find the layer break of" "path to an .iso file"
  [ -n "${DISK_APP_ANSWER}" ] || return 0
  DISK_LAYER_IMAGE="${DISK_APP_ANSWER}"
  disk_drive_tools_say disk_layer_run || :
}

disk_tools_tab_mount() {
  disk_app_ask "Image to mount, or a mounted folder to unmount" "path to an image or a folder"
  [ -n "${DISK_APP_ANSWER}" ] || return 0
  if [ -d "${DISK_APP_ANSWER}" ]; then
    DISK_MOUNT_POINT="${DISK_APP_ANSWER%/}"
    disk_drive_tools_say disk_unmount_run || :
    return 0
  fi
  DISK_MOUNT_IMAGE="${DISK_APP_ANSWER}"
  disk_drive_tools_say disk_mount_run || :
}

disk_frame_tools_speeds() {
  printf '%s\n' "Speed memory" ""
  disk_fp_rows="$(disk_speeds_rows)"
  if [ -z "${disk_fp_rows}" ]; then
    printf '%s\n' "No speeds remembered yet." "A write at a chosen speed remembers it for that disc ID and drive."
  else
    printf 'Drive\tDisc ID\tSpeed\n%s\n' "${disk_fp_rows}" | awk -F '\t' '{ printf "  %-26s%-14s%s\n", $1, $2, $3 }'
  fi
  printf '%s\n' "" "enter or esc back"
}
