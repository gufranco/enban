#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

ENBAN_VERSION="1.4.0"

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

disk_json_string() {
  printf '%s' "$1" | awk '
    BEGIN { for (i = 1; i < 32; i++) code[sprintf("%c", i)] = sprintf("\\u%04x", i) }
    function escape(s,   r, c, i) {
      r = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\") r = r "\\\\"
        else if (c == "\"") r = r "\\\""
        else if (c in code) r = r code[c]
        else r = r c
      }
      return r
    }
    { out = out (NR > 1 ? "\\n" : "") escape($0) }
    END { printf "\"%s\"", out }'
}
