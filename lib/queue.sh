#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_queue_rows() {
  awk -F '\t' '
    $0 ~ /^[ \t]*(#|$)/ { next }
    {
      if (NF == 1) { count = split($0, field, " ") } else { count = NF; for (i = 1; i <= NF; i++) field[i] = $i }
      speed = (count >= 3 && field[3] != "" ? field[3] : "auto")
      copies = (count >= 4 && field[4] != "" ? field[4] : "1")
      printf "%d\t%s\t%s\t%s\t%s\n", NR, field[1], (count >= 2 && field[2] != "" ? field[2] : "-"), speed, copies
      delete field
    }' "$1"
}

disk_queue_problem() {
  if [ "$2" = - ]; then
    printf 'name a drive after the image.\n'
    return 0
  fi
  if [ ! -f "$1" ]; then
    printf 'no image at %s.\n' "$1"
    return 0
  fi
  disk_qp_bytes="$(disk_file_bytes "$1")"
  if [ "${disk_qp_bytes}" -eq 0 ] || [ $((disk_qp_bytes % 2048)) -ne 0 ]; then
    printf '%s is not a disc image: its size is not a whole number of 2048-byte sectors.\n' "$1"
    return 0
  fi
  case "$3" in
  auto | [0-9] | [0-9][0-9] | [0-9][0-9][0-9]) : ;;
  *) printf 'the speed must be auto or a whole number, got: %s\n' "$3" ;;
  esac
  case "$4" in
  *[!0-9]* | '' | 0 | 0*) printf 'the copies must be a whole number from 1, got: %s\n' "$4" ;;
  *) : ;;
  esac
}

disk_queue_check() {
  while IFS="${DISK_TAB}" read -r disk_qk_line disk_qk_image disk_qk_drive disk_qk_speed disk_qk_copies; do
    disk_qk_problem="$(disk_queue_problem "${disk_qk_image}" "${disk_qk_drive}" "${disk_qk_speed}" "${disk_qk_copies}")"
    [ -z "${disk_qk_problem}" ] && continue
    disk_qk_first="$(printf '%s\n' "${disk_qk_problem}" | sed -n '1p')"
    disk_error "queue line ${disk_qk_line}: ${disk_qk_first}"
    return 1
  done <"$1"
}

disk_queue_drives() {
  cut -f 3 "$1" | awk '!seen[$0]++'
}

disk_queue_confirm() {
  disk_qc_total="$(grep -c '' "$2")"
  disk_qc_index=1
  while [ "${disk_qc_index}" -le "${disk_qc_total}" ]; do
    disk_qc_drive="$(sed -n "${disk_qc_index}p" "$2")"
    disk_qc_index=$((disk_qc_index + 1))
    disk_qc_name="$(disk_drive_word "${disk_qc_drive}")"
    disk_qc_count="$(cut -f 3 "$1" | grep -cxF -- "${disk_qc_drive}")"
    disk_qc_noun="$(disk_queue_plural "${disk_qc_count}" image)"
    printf 'Type %s to write %s to %s, or anything else to stop: ' "${disk_qc_name}" "${disk_qc_noun}" "${disk_qc_drive}" >&2
    disk_qc_answer=""
    IFS= read -r disk_qc_answer || disk_qc_answer=""
    [ "${disk_qc_answer}" = "${disk_qc_name}" ] && continue
    disk_error "cancelled, nothing was written."
    return 1
  done
}

disk_queue_plural() {
  case "$1" in
  1) printf '1 %s\n' "$2" ;;
  *) printf '%s %ss\n' "$1" "$2" ;;
  esac
}

disk_queue_wait() {
  disk_qw_waited=0
  while [ "${disk_qw_waited}" -le "${DISK_QUEUE_WAIT}" ]; do
    if disk_drive_read "$1" queue 2>/dev/null && [ "${DISK_DRIVE_STATUS}" = blank ]; then
      return 0
    fi
    sleep 1
    disk_qw_waited=$((disk_qw_waited + 1))
  done
  return 1
}

disk_queue_one() {
  if ! disk_queue_wait "$3"; then
    printf 'no blank disc in %s seconds\n' "${DISK_QUEUE_WAIT}" >"${DISK_QUEUE_DIR}/state.$1"
    return 1
  fi
  printf 'writing\n' >"${DISK_QUEUE_DIR}/state.$1"
  disk_qo_status=0
  disk_queue_burn "$2" "$3" "$4" >"${DISK_QUEUE_DIR}/log.$1" 2>&1 || disk_qo_status=1
  [ "${disk_qo_status}" -eq 0 ] && return 0
  sed -n 's/^enban: //p' "${DISK_QUEUE_DIR}/log.$1" | sed -n '$p' >"${DISK_QUEUE_DIR}/state.$1"
  return 1
}

disk_queue_burn() {
  DISK_DRIVE="$2"
  DISK_WRITE_IMAGE="$1"
  DISK_WRITE_SPEED="$3"
  [ "${DISK_WRITE_SPEED}" != auto ] || DISK_WRITE_SPEED=""
  DISK_WRITE_EJECT=y
  disk_write_check || return 1
  disk_write_go
}

disk_queue_hold() {
  disk_qh_waited=0
  while [ -e "${DISK_QUEUE_DIR}/paused" ] && [ "${disk_qh_waited}" -lt "${DISK_QUEUE_PAUSE_LIMIT}" ]; do
    printf 'paused\n' >"${DISK_QUEUE_DIR}/state.$1"
    sleep 1
    disk_qh_waited=$((disk_qh_waited + 1))
  done
}

disk_queue_finish() {
  printf 'done\n' >"${DISK_QUEUE_DIR}/state.$1"
  [ "${DISK_QUEUE_DELETE}" = y ] || return 0
  rm -f "$2" && : >"${DISK_QUEUE_DIR}/deleted.$1"
}

disk_queue_worker() {
  while IFS="${DISK_TAB}" read -r disk_qr_line disk_qr_image disk_qr_drive disk_qr_speed disk_qr_copies; do
    [ "${disk_qr_drive}" = "$1" ] || continue
    disk_queue_hold "${disk_qr_line}"
    disk_qr_copy=1
    while [ "${disk_qr_copy}" -le "${disk_qr_copies}" ]; do
      disk_queue_one "${disk_qr_line}" "${disk_qr_image}" "${disk_qr_drive}" "${disk_qr_speed}" || break
      disk_qr_copy=$((disk_qr_copy + 1))
    done
    [ "${disk_qr_copy}" -le "${disk_qr_copies}" ] || disk_queue_finish "${disk_qr_line}" "${disk_qr_image}"
  done <"$2"
}

disk_queue_start() {
  disk_qs_total="$(grep -c '' "$2")"
  disk_qs_index=1
  while [ "${disk_qs_index}" -le "${disk_qs_total}" ]; do
    disk_qs_drive="$(sed -n "${disk_qs_index}p" "$2")"
    disk_qs_index=$((disk_qs_index + 1))
    disk_queue_worker "${disk_qs_drive}" "$1" &
  done
  wait
}

disk_queue_report() {
  printf '%-3s%-24s %-18s %-6s %-7s %s\n' '#' Image Drive Speed Copies State
  disk_qt_row=0
  while IFS="${DISK_TAB}" read -r disk_qt_line disk_qt_image disk_qt_drive disk_qt_speed disk_qt_copies; do
    disk_qt_row=$((disk_qt_row + 1))
    disk_qt_state="not started"
    [ ! -f "${DISK_QUEUE_DIR}/state.${disk_qt_line}" ] || disk_qt_state="$(cat "${DISK_QUEUE_DIR}/state.${disk_qt_line}")"
    [ ! -e "${DISK_QUEUE_DIR}/deleted.${disk_qt_line}" ] || disk_qt_state="${disk_qt_state}, image deleted"
    disk_qt_shown="${disk_qt_speed}x"
    [ "${disk_qt_speed}" != auto ] || disk_qt_shown=auto
    printf '%-3s%-24s %-18s %-6s %-7s %s\n' "${disk_qt_row}" "${disk_qt_image##*/}" "${disk_qt_drive}" "${disk_qt_shown}" "${disk_qt_copies}" "${disk_qt_state}"
  done <"$1"
}

disk_queue_done() {
  disk_qd_total="$(grep -c '' "$1")"
  disk_qd_good="$(cat "${DISK_QUEUE_DIR}"/state.* 2>/dev/null | grep -cx 'done' || true)"
  if [ "${disk_qd_good}" -lt "${disk_qd_total}" ]; then
    disk_error "$((disk_qd_total - disk_qd_good)) of ${disk_qd_total} images failed; the table says why."
    return 1
  fi
  disk_qd_images="$(disk_queue_plural "${disk_qd_total}" image)"
  disk_qd_count="$(grep -c '' "$2")"
  disk_qd_drives="$(disk_queue_plural "${disk_qd_count}" drive)"
  disk_qd_line="Done. ${disk_qd_images} written to ${disk_qd_drives}."
  if disk_ui_out; then
    disk_ui_done "${disk_qd_line}"
    return 0
  fi
  printf '%s\n' "${disk_qd_line}"
}

disk_queue_prepare() {
  case "${DISK_QUEUE_WAIT}" in
  '' | *[!0-9]*)
    disk_error "ENBAN_QUEUE_WAIT must be a whole number of seconds, got: ${DISK_QUEUE_WAIT}"
    return 1
    ;;
  *) : ;;
  esac
  if [ ! -f "${DISK_QUEUE_FILE}" ]; then
    disk_error "no queue file at ${DISK_QUEUE_FILE}."
    return 1
  fi
  DISK_QUEUE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/enban-queue.XXXXXX")" || return 1
  disk_queue_rows "${DISK_QUEUE_FILE}" >"${DISK_QUEUE_DIR}/rows"
  disk_queue_drives "${DISK_QUEUE_DIR}/rows" >"${DISK_QUEUE_DIR}/drives"
  [ -s "${DISK_QUEUE_DIR}/rows" ] && return 0
  disk_error "${DISK_QUEUE_FILE} holds no images to write."
  return 1
}

disk_queue_steps() {
  disk_queue_check "${DISK_QUEUE_DIR}/rows" || return 1
  disk_queue_confirm "${DISK_QUEUE_DIR}/rows" "${DISK_QUEUE_DIR}/drives" || return 1
  disk_queue_start "${DISK_QUEUE_DIR}/rows" "${DISK_QUEUE_DIR}/drives"
  disk_queue_report "${DISK_QUEUE_DIR}/rows"
  disk_queue_done "${DISK_QUEUE_DIR}/rows" "${DISK_QUEUE_DIR}/drives"
}

disk_queue_run() {
  disk_qn_status=0
  if disk_queue_prepare; then
    disk_queue_steps || disk_qn_status=1
  else
    disk_qn_status=1
  fi
  [ -z "${DISK_QUEUE_DIR}" ] || rm -rf "${DISK_QUEUE_DIR}"
  return "${disk_qn_status}"
}
