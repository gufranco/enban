#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_job_launch() {
  DISK_APP_JOB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enban-job.XXXXXX")" || return 0
  DISK_APP_JOB_KIND="$2"
  DISK_APP_JOB_WHAT="$3"
  disk_job_run "$1" "${DISK_APP_JOB_DIR}" &
  DISK_APP_JOB_PID=$!
  DISK_APP_JOB=running
  DISK_APP_STATUS="$(disk_job_verb) Press c to cancel."
}

disk_job_run() {
  disk_jr_status=0
  "$1" >"$2/log" 2>&1 || disk_jr_status="$?"
  printf '%s\n' "${disk_jr_status}" >"$2/status"
}

disk_job_verb() {
  case "${DISK_APP_JOB_KIND}" in
  write) printf 'Writing.\n' ;;
  *) printf 'Reading.\n' ;;
  esac
}

disk_job_poll() {
  [ "${DISK_APP_JOB}" = running ] || return 0
  [ -f "${DISK_APP_JOB_DIR}/status" ] || return 0
  disk_jp_status="$(cat "${DISK_APP_JOB_DIR}/status")"
  DISK_APP_JOB_RESULT="$(cat "${DISK_APP_JOB_DIR}/log")"
  rm -rf "${DISK_APP_JOB_DIR}"
  DISK_APP_JOB=finished
  disk_app_drive
  DISK_APP_STATUS="The ${DISK_APP_JOB_KIND} failed; the result says why."
  [ "${disk_jp_status}" -ne 0 ] || DISK_APP_STATUS="$(printf '%s\n' "${DISK_APP_JOB_RESULT}" | sed -n '$p')"
}

disk_job_cancel() {
  disk_jc_children="$(pgrep -P "${DISK_APP_JOB_PID}" 2>/dev/null || true)"
  # shellcheck disable=SC2086
  kill "${DISK_APP_JOB_PID}" ${disk_jc_children} 2>/dev/null || true
  wait "${DISK_APP_JOB_PID}" 2>/dev/null || true
  rm -rf "${DISK_APP_JOB_DIR}"
  DISK_APP_JOB=finished
  DISK_APP_JOB_RESULT="Cancelled while writing. The disc may be unusable."
  [ "${DISK_APP_JOB_KIND}" = write ] || DISK_APP_JOB_RESULT="Cancelled while reading. The image is incomplete."
  DISK_APP_STATUS="Cancelled."
}

disk_job_busy() {
  [ "${DISK_APP_JOB}" = running ] || return 1
  DISK_APP_STATUS="A ${DISK_APP_JOB_KIND} is running. Press c on its tab to cancel it first."
}

disk_job_key() {
  [ "${DISK_APP_JOB}" != idle ] && [ "${DISK_APP_JOB_KIND}" = "$1" ] || return 1
  case "${DISK_APP_JOB}:$2" in
  running:c) disk_job_cancel ;;
  finished:enter) DISK_APP_JOB=idle ;;
  *) return 0 ;;
  esac
}

disk_job_pane() {
  [ "${DISK_APP_JOB}" != idle ] && [ "${DISK_APP_JOB_KIND}" = "$1" ] || return 1
  case "${DISK_APP_JOB}" in
  running)
    disk_jn_verb="$(disk_job_verb)"
    printf '%s\n' "${disk_jn_verb%.}" "" "${DISK_APP_JOB_WHAT}" "" "Press c to cancel."
    ;;
  *) printf '%s\n' "Result" "" "${DISK_APP_JOB_RESULT}" "" "Press Enter for the form." ;;
  esac
}

disk_job_box() {
  case "$1" in
  y) printf '[x] on' ;;
  *) printf '[ ] off' ;;
  esac
}

disk_job_flip() {
  case "$1" in
  y) printf 'n\n' ;;
  *) printf 'y\n' ;;
  esac
}

disk_job_row() {
  disk_jw_mark="  "
  [ "$1" -ne "$2" ] || disk_jw_mark="> "
  printf '%s%-11s%s\n' "${disk_jw_mark}" "$3" "$4"
}
