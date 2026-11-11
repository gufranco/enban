#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_mount_tool() {
  disk_mt_tool=udisksctl
  disk_mt_os="$(disk_os)"
  [ "${disk_mt_os}" != Darwin ] || disk_mt_tool=hdiutil
  command -v "${disk_mt_tool}" >/dev/null 2>&1 && return 0
  disk_error "$1 needs ${disk_mt_tool}. install udisks2 and try again."
  return 1
}

disk_mount_attach() {
  if [ "${disk_mt_tool}" = hdiutil ]; then
    disk_mount_hdiutil
    return
  fi
  disk_ma_device="$(udisksctl loop-setup --no-user-interaction -r -f "${DISK_MOUNT_IMAGE}" | sed -n 's/^Mapped file .* as \(.*\)\.$/\1/p')"
  [ -n "${disk_ma_device}" ] || return 1
  disk_ma_point="$(udisksctl mount --no-user-interaction -b "${disk_ma_device}" | sed -n 's/^Mounted .* at \(.*\)$/\1/p')"
  if [ -z "${disk_ma_point}" ]; then
    udisksctl loop-delete --no-user-interaction -b "${disk_ma_device}" >/dev/null
    return 1
  fi
  printf '%s\n' "${disk_ma_point}"
}

disk_mount_hdiutil() {
  disk_mh_rows="$(hdiutil attach -readonly -nobrowse "${DISK_MOUNT_IMAGE}")" || return 1
  printf '%s\n' "${disk_mh_rows}" | awk -F '\t' 'NF > 2 && $3 != "" { point = $3 } END { print point }'
}

disk_mount_run() {
  if [ ! -f "${DISK_MOUNT_IMAGE}" ]; then
    disk_error "no image at ${DISK_MOUNT_IMAGE}."
    return 1
  fi
  disk_mount_tool mount || return 1
  disk_mr_point="$(disk_mount_attach 2>/dev/null)" || disk_mr_point=""
  if [ -z "${disk_mr_point}" ]; then
    disk_error "unable to mount ${DISK_MOUNT_IMAGE}."
    return 1
  fi
  disk_raw_done "Done. ${DISK_MOUNT_IMAGE} is mounted read-only at ${disk_mr_point}."
}

disk_mount_source() {
  awk -v want="$1" '{ point = $2; gsub(/\\040/, " ", point); if (point == want) { print $1; exit } }' /proc/mounts
}

disk_mount_detach() {
  if [ "${disk_mt_tool}" = hdiutil ]; then
    hdiutil detach "${DISK_MOUNT_POINT}" >/dev/null
    return
  fi
  disk_md_device="$(disk_mount_source "${DISK_MOUNT_POINT}")"
  [ -n "${disk_md_device}" ] || return 1
  udisksctl unmount --no-user-interaction -b "${disk_md_device}" >/dev/null &&
    udisksctl loop-delete --no-user-interaction -b "${disk_md_device}" >/dev/null
}

disk_unmount_run() {
  if [ ! -d "${DISK_MOUNT_POINT}" ]; then
    disk_error "no folder at ${DISK_MOUNT_POINT}."
    return 1
  fi
  disk_mount_tool unmount || return 1
  if ! disk_mount_detach 2>/dev/null; then
    disk_error "unable to unmount ${DISK_MOUNT_POINT}. close what uses it and try again."
    return 1
  fi
  disk_raw_done "Done. ${DISK_MOUNT_POINT} is unmounted."
}
