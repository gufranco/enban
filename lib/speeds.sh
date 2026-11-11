#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_speeds_file() {
  printf '%s/speeds.tsv\n' "${DISK_DATA}"
}

disk_speeds_drive() {
  printf '%s %s\n' "${DISK_DRIVE_VENDOR}" "${DISK_DRIVE_PRODUCT}"
}

disk_speeds_find() {
  disk_pf_file="$(disk_speeds_file)"
  [ -f "${disk_pf_file}" ] || return 0
  awk -F '\t' -v drive="$1" -v media="$2" '$1 == drive && $2 == media { speed = $3 } END { print speed }' "${disk_pf_file}"
}

disk_speeds_recall() {
  [ -z "${DISK_WRITE_SPEED}" ] && [ -n "${DISK_DRIVE_MEDIA_ID}" ] || return 0
  disk_pr_drive="$(disk_speeds_drive)"
  disk_pr_speed="$(disk_speeds_find "${disk_pr_drive}" "${DISK_DRIVE_MEDIA_ID}")"
  [ -n "${disk_pr_speed}" ] || return 0
  DISK_WRITE_SPEED="${disk_pr_speed}"
  disk_say "Writing at ${disk_pr_speed}x, the speed remembered for ${DISK_DRIVE_MEDIA_ID} in this drive."
}

disk_speeds_keep() {
  [ -n "${DISK_WRITE_SPEED}" ] && [ -n "${DISK_DRIVE_MEDIA_ID}" ] || return 0
  if ! mkdir -p "${DISK_DATA}" 2>/dev/null; then
    disk_warning "the disc is written, but its speed is not remembered: ${DISK_DATA} is not writable."
    return 0
  fi
  if ! disk_speeds_lock; then
    disk_warning "the disc is written, but its speed is not remembered: ${DISK_DATA}/.speeds.lock stayed taken."
    return 0
  fi
  disk_speeds_merge
  rm -f "${DISK_DATA}/.speeds.lock"
}

disk_speeds_lock() {
  disk_pc_tries=0
  while ! (set -C && : >"${DISK_DATA}/.speeds.lock") 2>/dev/null; do
    disk_pc_tries=$((disk_pc_tries + 1))
    [ "${disk_pc_tries}" -lt 25 ] || return 1
    sleep 0.2
  done
}

disk_speeds_merge() {
  disk_pk_file="$(disk_speeds_file)"
  disk_pk_drive="$(disk_speeds_drive)"
  disk_pk_new="${DISK_DATA}/.speeds.$$"
  : >"${disk_pk_new}"
  [ ! -f "${disk_pk_file}" ] || awk -F '\t' -v drive="${disk_pk_drive}" -v media="${DISK_DRIVE_MEDIA_ID}" '!($1 == drive && $2 == media)' "${disk_pk_file}" >"${disk_pk_new}"
  printf '%s\t%s\t%s\n' "${disk_pk_drive}" "${DISK_DRIVE_MEDIA_ID}" "${DISK_WRITE_SPEED}" >>"${disk_pk_new}"
  mv -f "${disk_pk_new}" "${disk_pk_file}"
}

disk_speeds_rows() {
  disk_pw_file="$(disk_speeds_file)"
  [ -s "${disk_pw_file}" ] || return 0
  LC_ALL=C sort "${disk_pw_file}" | awk -F '\t' '{ printf "%s\t%s\t%sx\n", $1, $2, $3 }'
}

disk_speeds_run() {
  disk_pl_rows="$(disk_speeds_rows)"
  if [ -z "${disk_pl_rows}" ]; then
    disk_say "No speeds remembered yet. a write with --speed remembers its speed for that disc ID and drive."
    return 0
  fi
  if disk_ui_out; then
    printf 'Drive\tDisc ID\tSpeed\n%s\n' "${disk_pl_rows}" | disk_ui_table
    return 0
  fi
  printf '%s\n' "${disk_pl_rows}" | awk -F '\t' '{ printf "%-28s%-16s%s\n", $1, $2, $3 }'
}
