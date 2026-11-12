#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_job_launch() {
  DISK_APP_JOB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enban-job.XXXXXX")" || return 0
  DISK_APP_JOB_KIND="$2"
  DISK_APP_JOB_WHAT="$3"
  DISK_APP_CLOSE_AFTER="${4:-n}"
  DISK_JOB_NOTE="${DISK_APP_JOB_DIR}/part"
  disk_job_run "$1" "${DISK_APP_JOB_DIR}" &
  DISK_APP_JOB_PID=$!
  DISK_APP_JOB=running
  DISK_APP_STATUS="$(disk_job_verb) Press c to cancel."
  disk_log_add INFO "Started ${DISK_APP_JOB_KIND}: ${DISK_APP_JOB_WHAT}"
}

disk_job_run() {
  disk_jr_status=0
  "$1" >"$2/log" 2>&1 || disk_jr_status="$?"
  printf '%s\n' "${disk_jr_status}" >"$2/status"
}

disk_job_verb() {
  case "${DISK_APP_JOB_KIND}" in
  write) printf 'Writing.\n' ;;
  verify) printf 'Verifying.\n' ;;
  build) printf 'Building.\n' ;;
  erase) printf 'Erasing.\n' ;;
  checksum) printf 'Checking.\n' ;;
  queue) printf 'Writing the queue.\n' ;;
  convert) printf 'Converting.\n' ;;
  discovery) printf 'Testing.\n' ;;
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
  disk_log_job_end "${disk_jp_status}"
  disk_job_bell
  [ "${disk_jp_status}" -ne 0 ] || [ "${DISK_APP_CLOSE_AFTER}" = n ] || DISK_APP_QUIT=y
}

disk_job_bell() {
  [ "${DISK_EVENT_BELL}" = y ] || return 0
  printf '\a'
}

disk_job_ask_cancel() {
  [ "${DISK_EVENT_CONFIRM}" = y ] || {
    disk_job_cancel
    return
  }
  disk_app_ask "Cancel the ${DISK_APP_JOB_KIND}? Type y to cancel, anything else to go on" "y"
  if [ "${DISK_APP_ANSWER}" = y ]; then
    disk_job_cancel
    return
  fi
  DISK_APP_STATUS="The ${DISK_APP_JOB_KIND} goes on. Press c to cancel."
}

disk_job_cancel() {
  disk_jc_tree="$(disk_job_frozen "${DISK_APP_JOB_PID}")"
  # shellcheck disable=SC2086
  kill ${disk_jc_tree} 2>/dev/null || true
  # shellcheck disable=SC2086
  kill -CONT ${disk_jc_tree} 2>/dev/null || true
  wait "${DISK_APP_JOB_PID}" 2>/dev/null || true
  DISK_APP_STATUS="$(disk_job_drop_part)"
  rm -rf "${DISK_APP_JOB_DIR}"
  DISK_APP_JOB=finished
  DISK_APP_JOB_RESULT="$(disk_job_cancelled)"
  disk_log_add WARN "Cancelled ${DISK_APP_JOB_KIND}: ${DISK_APP_JOB_WHAT}"
}

disk_job_cancelled() {
  case "${DISK_APP_JOB_KIND}" in
  write) printf 'Cancelled while writing. The disc may be unusable.\n' ;;
  verify) printf 'Cancelled while verifying. Nothing on the disc changed.\n' ;;
  build) printf 'Cancelled while building. No image was written.\n' ;;
  erase) printf 'Cancelled while erasing. The disc may be unusable.\n' ;;
  checksum) printf 'Cancelled while checking. Nothing changed.\n' ;;
  queue) printf 'Cancelled while writing the queue. A disc in a drive may be unusable.\n' ;;
  discovery) printf 'Cancelled while testing. The disc holds part of the test data.\n' ;;
  convert) printf 'Cancelled while converting. No ISO was written.\n' ;;
  *) printf 'Cancelled while reading. The image is incomplete.\n' ;;
  esac
}

disk_job_drop_part() {
  if [ ! -f "${DISK_JOB_NOTE}" ]; then
    printf 'Cancelled.\n'
    return 0
  fi
  if [ "${DISK_EVENT_CLEAN}" = n ]; then
    disk_jd_first="$(sed -n '1p' "${DISK_JOB_NOTE}")"
    printf 'Cancelled. The half-written %s is kept.\n' "${disk_jd_first}"
    return 0
  fi
  while IFS= read -r disk_jd_part; do
    rm -rf "${disk_jd_part}"
  done <"${DISK_JOB_NOTE}"
  printf 'Cancelled. The half-written files are deleted.\n'
}

disk_job_note() {
  [ -n "${DISK_JOB_NOTE}" ] || return 0
  printf '%s\n' "$@" >"${DISK_JOB_NOTE}"
}

disk_job_frozen() {
  disk_jf_tree=""
  disk_jf_round=0
  while [ "${disk_jf_round}" -lt "${DISK_JOB_DEPTH}" ]; do
    disk_jf_next="$(disk_job_tree "$1")"
    # shellcheck disable=SC2086
    kill -STOP ${disk_jf_next} 2>/dev/null || true
    [ "${disk_jf_next}" != "${disk_jf_tree}" ] || break
    disk_jf_tree="${disk_jf_next}"
    disk_jf_round=$((disk_jf_round + 1))
  done
  printf '%s\n' "${disk_jf_tree}"
}

disk_job_tree() {
  disk_jt_all="$1"
  disk_jt_level="$1"
  disk_jt_depth=0
  while [ -n "${disk_jt_level}" ] && [ "${disk_jt_depth}" -lt "${DISK_JOB_DEPTH}" ]; do
    # shellcheck disable=SC2086
    disk_jt_level="$(disk_job_children ${disk_jt_level})"
    disk_jt_all="${disk_jt_all} ${disk_jt_level}"
    disk_jt_depth=$((disk_jt_depth + 1))
  done
  printf '%s\n' "${disk_jt_all}"
}

disk_job_children() {
  for disk_jh_pid in "$@"; do
    pgrep -P "${disk_jh_pid}" 2>/dev/null || :
  done | tr '\n' ' ' | sed 's/ *$//'
}

disk_job_image() {
  if [ ! -f "$1" ]; then
    DISK_APP_STATUS="No image at $1."
    return 1
  fi
  disk_ji_bytes="$(disk_file_bytes "$1")"
  if [ "${disk_ji_bytes}" -eq 0 ] || [ $((disk_ji_bytes % 2048)) -ne 0 ]; then
    DISK_APP_STATUS="$1 is not a disc image: its size is not whole 2048-byte sectors."
    return 1
  fi
  DISK_APP_IMAGE_SECTORS=$((disk_ji_bytes / 2048))
}

disk_job_busy() {
  [ "${DISK_APP_JOB}" = running ] || return 1
  DISK_APP_STATUS="A ${DISK_APP_JOB_KIND} is running. Press c on its tab to cancel it first."
}

disk_job_typed() {
  disk_jy_name="$(disk_drive_word "${DISK_DRIVE}")"
  disk_jy_verb="${1:-write}"
  disk_app_ask "Type ${disk_jy_name} to ${disk_jy_verb}, or anything else to stop" "${disk_jy_name}"
  [ "${DISK_APP_ANSWER}" = "${disk_jy_name}" ] && return 0
  case "${disk_jy_verb}" in
  write) DISK_APP_STATUS="Nothing was written." ;;
  erase) DISK_APP_STATUS="Nothing was erased." ;;
  *) DISK_APP_STATUS="Nothing was touched." ;;
  esac
  return 1
}

disk_job_key() {
  [ "${DISK_APP_JOB}" != idle ] && [ "${DISK_APP_JOB_KIND}" = "$1" ] || return 1
  case "${DISK_APP_JOB}:$2" in
  running:c) disk_job_ask_cancel ;;
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
