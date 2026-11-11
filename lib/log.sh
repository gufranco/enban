#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_log_add() {
  [ -n "${DISK_APP_LOG}" ] || return 0
  disk_lg_time="$(date -u +%H:%M:%S)"
  printf '%s %-5s %s\n' "${disk_lg_time}" "$1" "$2" >>"${DISK_APP_LOG}"
}

disk_log_open() {
  DISK_APP_LOG="$(mktemp "${TMPDIR:-/tmp}/enban-log.XXXXXX")" || DISK_APP_LOG=""
}

disk_log_folder() {
  printf '%s/logs\n' "${DISK_DATA}"
}

disk_log_close() {
  [ -n "${DISK_APP_LOG}" ] || return 0
  disk_lc_folder="$(disk_log_folder)"
  disk_lc_day="$(date -u +%Y-%m-%d)"
  if ! { mkdir -p "${disk_lc_folder}" && cat "${DISK_APP_LOG}" >>"${disk_lc_folder}/${disk_lc_day}.log"; } 2>/dev/null; then
    disk_warning "unable to keep the log in ${disk_lc_folder}."
  fi
  rm -f "${DISK_APP_LOG}"
  DISK_APP_LOG=""
}

disk_log_job_end() {
  if [ "$1" -eq 0 ]; then
    disk_log_add INFO "Finished ${DISK_APP_JOB_KIND}: ${DISK_APP_STATUS}"
    return 0
  fi
  disk_le_reason="$(printf '%s\n' "${DISK_APP_JOB_RESULT}" | sed -n 's/^enban: //p' | sed -n '$p')"
  disk_log_add ERROR "The ${DISK_APP_JOB_KIND} failed: ${disk_le_reason:-it stopped without a reason.}"
}
