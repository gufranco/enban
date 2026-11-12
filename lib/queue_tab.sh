#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_queue_tab_key() {
  if [ "$1" = p ] && disk_queue_live; then
    disk_queue_tab_pause
    return 0
  fi
  disk_job_key queue "$1" && return 0
  disk_qa_count="$(disk_queue_tab_count)"
  case "$1" in
  up) [ "${DISK_APP_Q_FOCUS}" -le 0 ] || DISK_APP_Q_FOCUS=$((DISK_APP_Q_FOCUS - 1)) ;;
  down) [ "${DISK_APP_Q_FOCUS}" -ge $((disk_qa_count - 1)) ] || DISK_APP_Q_FOCUS=$((DISK_APP_Q_FOCUS + 1)) ;;
  a) disk_queue_tab_add ;;
  x)
    DISK_APP_Q_MARKS=""
    disk_queue_tab_remove "${disk_qa_count}"
    ;;
  J)
    DISK_APP_Q_MARKS=""
    disk_queue_tab_move "${disk_qa_count}" 1
    ;;
  K)
    DISK_APP_Q_MARKS=""
    disk_queue_tab_move "${disk_qa_count}" -1
    ;;
  enter) disk_queue_tab_edit "${disk_qa_count}" ;;
  o) disk_queue_tab_save ;;
  v) DISK_APP_Q_VERIFY="$(disk_job_flip "${DISK_APP_Q_VERIFY}")" ;;
  d) DISK_APP_Q_DELETE="$(disk_job_flip "${DISK_APP_Q_DELETE}")" ;;
  space) disk_queue_tab_mark "${disk_qa_count}" ;;
  s) disk_queue_tab_start ;;
  *) return 0 ;;
  esac
}

disk_queue_tab_count() {
  if [ -z "${DISK_APP_Q_ROWS}" ]; then
    printf '0\n'
    return 0
  fi
  printf '%s\n' "${DISK_APP_Q_ROWS}" | wc -l | tr -d '[:space:]'
}

disk_queue_tab_add() {
  disk_app_ask "Image to queue" "path to an .iso file"
  [ -n "${DISK_APP_ANSWER}" ] || return 0
  disk_job_image "${DISK_APP_ANSWER}" || return 0
  disk_qd_image="${DISK_APP_ANSWER}"
  disk_qd_drive="${DISK_DRIVE}"
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    disk_app_ask "Drive to write ${disk_qd_image##*/} to" "/dev/sr0"
    disk_qd_drive="${DISK_APP_ANSWER}"
  fi
  [ -n "${disk_qd_drive}" ] || return 0
  DISK_APP_Q_FOCUS="$(disk_queue_tab_count)"
  disk_qd_row="$(printf '%s\t%s\tauto\t1' "${disk_qd_image}" "${disk_qd_drive}")"
  DISK_APP_Q_ROWS="$(printf '%s\n%s\n' "${DISK_APP_Q_ROWS}" "${disk_qd_row}" | sed '/^$/d')"
  DISK_APP_STATUS="Queued ${disk_qd_image##*/} for ${disk_qd_drive}."
}

disk_queue_tab_remove() {
  [ "$1" -gt 0 ] || return 0
  disk_qx_line=$((DISK_APP_Q_FOCUS + 1))
  disk_qx_image="$(printf '%s\n' "${DISK_APP_Q_ROWS}" | sed -n "${disk_qx_line}p" | cut -f 1)"
  DISK_APP_Q_ROWS="$(printf '%s\n' "${DISK_APP_Q_ROWS}" | sed "${disk_qx_line}d")"
  [ "${DISK_APP_Q_FOCUS}" -lt $(($1 - 1)) ] || [ "${DISK_APP_Q_FOCUS}" -eq 0 ] || DISK_APP_Q_FOCUS=$((DISK_APP_Q_FOCUS - 1))
  DISK_APP_STATUS="Removed ${disk_qx_image##*/}."
}

disk_queue_tab_move() {
  disk_qm_to=$((DISK_APP_Q_FOCUS + $2))
  [ "${disk_qm_to}" -ge 0 ] && [ "${disk_qm_to}" -lt "$1" ] || return 0
  DISK_APP_Q_ROWS="$(printf '%s\n' "${DISK_APP_Q_ROWS}" | awk -v a=$((DISK_APP_Q_FOCUS + 1)) -v b=$((disk_qm_to + 1)) '
    { row[NR] = $0 }
    END { swap = row[a]; row[a] = row[b]; row[b] = swap; for (i = 1; i <= NR; i++) print row[i] }')"
  DISK_APP_Q_FOCUS="${disk_qm_to}"
}

disk_queue_tab_edit() {
  [ "$1" -gt 0 ] || return 0
  disk_app_ask "Speed, auto for the drive's choice" "auto"
  case "${DISK_APP_ANSWER}" in
  auto | [0-9] | [0-9][0-9] | [0-9][0-9][0-9]) disk_qe_speed="${DISK_APP_ANSWER}" ;;
  *)
    DISK_APP_STATUS="The speed must be auto or a whole number, such as 8."
    return 0
    ;;
  esac
  disk_app_ask "Copies" "1"
  case "${DISK_APP_ANSWER}" in
  '' | *[!0-9]* | 0*)
    DISK_APP_STATUS="The copies must be a whole number from 1."
    return 0
    ;;
  *) disk_queue_tab_set "${disk_qe_speed}" "${DISK_APP_ANSWER}" ;;
  esac
}

disk_queue_tab_set() {
  disk_qz_rows="${DISK_APP_Q_MARKS:- $((DISK_APP_Q_FOCUS + 1)) }"
  DISK_APP_Q_ROWS="$(printf '%s\n' "${DISK_APP_Q_ROWS}" | awk -F "${DISK_TAB}" -v OFS="${DISK_TAB}" -v rows="${disk_qz_rows}" -v speed="$1" -v copies="$2" '
    index(rows, " " NR " ") { $3 = speed; $4 = copies } { print }')"
  disk_qz_count="$(printf '%s\n' "${disk_qz_rows}" | awk '{ print NF }')"
  disk_qz_noun="$(disk_queue_plural "${disk_qz_count}" image)"
  DISK_APP_STATUS="Set ${disk_qz_noun} to speed $1, $2 copies."
}

disk_queue_tab_mark() {
  [ "$1" -gt 0 ] || return 0
  disk_qv_row=" $((DISK_APP_Q_FOCUS + 1)) "
  case "${DISK_APP_Q_MARKS}" in
  *"${disk_qv_row}"*) DISK_APP_Q_MARKS="$(printf '%s' "${DISK_APP_Q_MARKS}" | sed "s/${disk_qv_row}/ /")" ;;
  *) DISK_APP_Q_MARKS="${DISK_APP_Q_MARKS:- }$((DISK_APP_Q_FOCUS + 1)) " ;;
  esac
  [ "${DISK_APP_Q_MARKS}" != " " ] || DISK_APP_Q_MARKS=""
}

disk_queue_tab_pause() {
  disk_qp_flag="${DISK_APP_JOB_DIR}/queue/paused"
  if [ -e "${disk_qp_flag}" ]; then
    rm -f "${disk_qp_flag}"
    DISK_APP_STATUS="The queue goes on with the next image."
    return 0
  fi
  : >"${disk_qp_flag}"
  DISK_APP_STATUS="The queue pauses before its next image. Press p to go on."
}

disk_queue_tab_save() {
  if [ -z "${DISK_APP_Q_ROWS}" ]; then
    DISK_APP_STATUS="Add an image first: press a."
    return 0
  fi
  disk_app_ask "Queue file to create" "path to a new .queue file"
  [ -n "${DISK_APP_ANSWER}" ] || return 0
  if [ -e "${DISK_APP_ANSWER}" ]; then
    DISK_APP_STATUS="${DISK_APP_ANSWER} already exists. Choose a new name."
    return 0
  fi
  printf '%s\n' "${DISK_APP_Q_ROWS}" >"${DISK_APP_ANSWER}"
  DISK_APP_STATUS="Saved the queue to ${DISK_APP_ANSWER}."
}

disk_queue_tab_start() {
  disk_job_busy && return 0
  if [ -z "${DISK_APP_Q_ROWS}" ]; then
    DISK_APP_STATUS="Add an image first: press a."
    return 0
  fi
  disk_queue_tab_typed || return 0
  disk_qs_count="$(disk_queue_tab_count)"
  disk_qs_noun="$(disk_queue_plural "${disk_qs_count}" image)"
  disk_job_launch disk_queue_tab_steps queue "${disk_qs_noun}"
}

disk_queue_tab_typed() {
  disk_qy_drives="$(printf '%s\n' "${DISK_APP_Q_ROWS}" | cut -f 2 | awk '!seen[$0]++')"
  disk_qy_total="$(printf '%s\n' "${disk_qy_drives}" | wc -l | tr -d '[:space:]')"
  disk_qy_index=1
  while [ "${disk_qy_index}" -le "${disk_qy_total}" ]; do
    disk_qy_drive="$(printf '%s\n' "${disk_qy_drives}" | sed -n "${disk_qy_index}p")"
    disk_qy_index=$((disk_qy_index + 1))
    disk_qy_word="$(disk_drive_word "${disk_qy_drive}")"
    disk_app_ask "Type ${disk_qy_word} to write to ${disk_qy_drive}, or anything else to stop" "${disk_qy_word}"
    [ "${DISK_APP_ANSWER}" = "${disk_qy_word}" ] && continue
    DISK_APP_STATUS="Nothing was written."
    return 1
  done
}

disk_queue_tab_steps() {
  DISK_WRITE_VERIFY="${DISK_APP_Q_VERIFY}"
  DISK_QUEUE_DELETE="${DISK_APP_Q_DELETE}"
  DISK_QUEUE_DIR="${DISK_APP_JOB_DIR}/queue"
  mkdir -p "${DISK_QUEUE_DIR}"
  printf '%s\n' "${DISK_APP_Q_ROWS}" | awk '{ print NR "\t" $0 }' >"${DISK_QUEUE_DIR}/rows"
  disk_queue_drives "${DISK_QUEUE_DIR}/rows" >"${DISK_QUEUE_DIR}/drives"
  disk_queue_start "${DISK_QUEUE_DIR}/rows" "${DISK_QUEUE_DIR}/drives"
  disk_queue_report "${DISK_QUEUE_DIR}/rows"
  disk_queue_done "${DISK_QUEUE_DIR}/rows" "${DISK_QUEUE_DIR}/drives"
}
