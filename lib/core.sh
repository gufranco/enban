#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

ENBAN_VERSION="0.1.0"

disk_version() {
  printf '%s %s\n' "${1:-${DISK_PROG}}" "${ENBAN_VERSION}"
}

disk_say() {
  printf '%s\n' "$1"
}

disk_log() {
  disk_say "$1$2"
}

disk_warning() {
  if disk_ui_err; then
    disk_ui_log WARN "$*"
    return 0
  fi
  disk_log "${DISK_PROG}: warning: " "$*" >&2
}

disk_error() {
  if disk_ui_err; then
    disk_ui_log ERROR "$*"
    return 0
  fi
  disk_log "${DISK_PROG}: " "$*" >&2
}

disk_os() {
  if [ -z "${DISK_OS:-}" ]; then
    DISK_OS="$(uname -s)"
  fi
  printf '%s\n' "${DISK_OS}"
}
