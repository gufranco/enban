#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_queue_live() {
  [ "${DISK_APP_JOB}" = running ] && [ "${DISK_APP_JOB_KIND}" = queue ]
}

disk_frame_queue() {
  [ "${DISK_APP_JOB}:${DISK_APP_JOB_KIND}" != finished:queue ] || {
    disk_job_pane queue
    return 0
  }
  disk_fq_count="$(disk_queue_tab_count)"
  disk_fq_noun="$(disk_queue_plural "${disk_fq_count}" image)"
  printf 'Write queue   %s\n\n' "${disk_fq_noun}"
  disk_queue_table
  disk_fq_verify="$(disk_job_box "${DISK_APP_Q_VERIFY}")"
  disk_fq_delete="$(disk_job_box "${DISK_APP_Q_DELETE}")"
  printf '\n%s\n' "After each image"
  printf '  %-15s %s\n' "Eject and wait" "always" "Verify" "${disk_fq_verify}" "Delete image" "${disk_fq_delete}"
  printf '\n'
  if disk_queue_live; then
    printf '%s\n' "p pause or go on   c cancel"
    return 0
  fi
  printf '%s\n' "a add   x remove   J K move   space mark   enter edit" "v verify   d delete   o save   s start"
}

disk_queue_table() {
  if [ -z "${DISK_APP_Q_ROWS}" ]; then
    printf '%s\n' "  Nothing queued yet. Press a to add an image."
    return 0
  fi
  disk_qb_dir=""
  ! disk_queue_live || disk_qb_dir="${DISK_APP_JOB_DIR}/queue"
  printf '  %-3s%-17s %-12s %-5s %-6s %s\n' '#' Image Drive Speed Copies State
  printf '%s\n' "${DISK_APP_Q_ROWS}" | awk -F "${DISK_TAB}" -v focus="${DISK_APP_Q_FOCUS}" -v dir="${disk_qb_dir}" -v marks="${DISK_APP_Q_MARKS}" '
    {
      state = "waiting"
      if (dir != "") { file = dir "/state." NR; if ((getline line < file) > 0) state = line; close(file) }
      name = $1; sub(/.*\//, "", name)
      speed = ($3 == "auto" ? "auto" : $3 "x")
      mark = (index(marks, " " NR " ") ? "*" : " ")
      printf "%s%-3s%-17s %-12s %-5s %-6s %s\n", (NR - 1 == focus ? ">" : " ") mark, NR, substr(name, 1, 17), substr($2, 1, 12), speed, $4, state
    }'
}

disk_queue_side() {
  printf '%s\n' "Queue"
  if [ -z "${DISK_APP_Q_ROWS}" ]; then
    printf '%s\n' "Nothing queued yet."
    return 0
  fi
  disk_qi_count="$(disk_queue_tab_count)"
  disk_qi_drives="$(printf '%s\n' "${DISK_APP_Q_ROWS}" | cut -f 2 | awk '!seen[$0]++' | wc -l | tr -d '[:space:]')"
  disk_qi_noun="$(disk_queue_plural "${disk_qi_drives}" drive)"
  printf 'Images       %s on %s\n' "${disk_qi_count}" "${disk_qi_noun}"
  printf '\n%s\n' "Drives"
  printf '%s\n' "${DISK_APP_Q_ROWS}" | cut -f 2 | awk '
    { count[$0]++; if (!($0 in seen)) { seen[$0] = 1; order[++n] = $0 } }
    END { for (i = 1; i <= n; i++) printf "  %-20s %d image%s\n", order[i], count[order[i]], (count[order[i]] == 1 ? "" : "s") }'
}
