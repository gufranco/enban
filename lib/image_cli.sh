#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_label() {
  disk_options 2 "$@" || return 1
  disk_only_for label || return 1
  if [ -z "${DISK_OPERAND_TWO}" ]; then
    disk_cli_hint "label needs an image and the new label"
    return 1
  fi
  DISK_LABEL_IMAGE="${DISK_OPERAND}"
  DISK_LABEL_NAME="${DISK_OPERAND_TWO}"
  disk_label_run
}

disk_layerbreak() {
  disk_options 1 "$@" || return 1
  disk_only_for layerbreak || return 1
  if [ -z "${DISK_OPERAND}" ]; then
    disk_cli_hint "layerbreak needs an image"
    return 1
  fi
  DISK_LAYER_IMAGE="${DISK_OPERAND}"
  disk_layer_run
}

disk_mount() {
  disk_options 1 "$@" || return 1
  disk_only_for mount || return 1
  if [ -z "${DISK_OPERAND}" ]; then
    disk_cli_hint "mount needs an image"
    return 1
  fi
  DISK_MOUNT_IMAGE="${DISK_OPERAND}"
  disk_mount_run
}

disk_unmount() {
  disk_options 1 "$@" || return 1
  disk_only_for unmount || return 1
  if [ -z "${DISK_OPERAND}" ]; then
    disk_cli_hint "unmount needs the folder the image is mounted at"
    return 1
  fi
  DISK_MOUNT_POINT="${DISK_OPERAND%/}"
  disk_unmount_run
}

disk_speeds() {
  disk_options 0 "$@" || return 1
  disk_only_for speeds || return 1
  disk_speeds_run
}
