#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_discovery_pattern() {
  awk -v first="$1" -v count="$2" 'BEGIN {
    for (s = first; s < first + count; s++) {
      line = sprintf("enban discovery %010d.....\n", s)
      block = ""
      for (i = 0; i < 64; i++) block = block line
      printf "%s", block
    }
  }'
}

disk_discovery_folder() {
  printf '%s/discovery\n' "${DISK_DATA}"
}

disk_discovery_check() {
  disk_drive_read "${DISK_DRIVE}" discovery || return 1
  if [ "${DISK_DRIVE_STATUS}" != blank ]; then
    disk_error "stopped: the disc in ${DISK_DRIVE} is not blank."
    return 1
  fi
  DISK_DISCOVERY_COUNT="${DISK_DISCOVERY_SECTORS:-${DISK_DRIVE_FREE}}"
  if [ "${DISK_DISCOVERY_COUNT}" -gt "${DISK_DRIVE_FREE}" ]; then
    disk_error "stopped: the disc in ${DISK_DRIVE} has ${DISK_DRIVE_FREE} free sectors, not ${DISK_DISCOVERY_COUNT}."
    return 1
  fi
  disk_discovery_csv_path || return 1
}

disk_discovery_csv_path() {
  if [ -z "${DISK_DISCOVERY_CSV}" ]; then
    disk_dp_folder="$(disk_discovery_folder)"
    disk_dp_stamp="$(date -u +%Y%m%d-%H%M%S)"
    DISK_DISCOVERY_CSV="${disk_dp_folder}/${disk_dp_stamp}.csv"
  fi
  if [ -e "${DISK_DISCOVERY_CSV}" ]; then
    disk_error "stopped: ${DISK_DISCOVERY_CSV} already exists."
    return 1
  fi
}

disk_discovery_confirm() {
  disk_dc_name="${DISK_DRIVE##*/}"
  printf 'Type %s to fill the disc with test data, or anything else to stop: ' "${disk_dc_name}" >&2
  disk_dc_answer=""
  IFS= read -r disk_dc_answer || disk_dc_answer=""
  [ "${disk_dc_answer}" = "${disk_dc_name}" ] && return 0
  disk_error "cancelled, nothing was written."
  return 1
}

disk_discovery_write() {
  disk_dw_log="$(mktemp "${TMPDIR:-/tmp}/enban-discovery.XXXXXX")" || return 1
  set -- -as cdrecord -v "dev=${DISK_DRIVE}" -dao
  [ -z "${DISK_WRITE_SPEED}" ] || set -- "$@" "speed=${DISK_WRITE_SPEED}"
  [ "${DISK_WRITE_TEST}" = n ] || set -- "$@" -dummy
  disk_dw_status=0
  disk_discovery_pattern 0 "${DISK_DISCOVERY_COUNT}" | xorriso "$@" "tsize=$((DISK_DISCOVERY_COUNT * 2048))" - >"${disk_dw_log}" 2>&1 || disk_dw_status="$?"
  disk_dw_reason="$(sed -n 's/^xorriso : FAILURE : //p' "${disk_dw_log}" | sed -n '1p')"
  rm -f "${disk_dw_log}"
  [ "${disk_dw_status}" -eq 0 ] && return 0
  disk_error "the write to ${DISK_DRIVE} failed: ${disk_dw_reason:-xorriso exited with ${disk_dw_status}.}"
  return 1
}

disk_discovery_chunk() {
  disk_dk_dir="$1"
  dd if="${DISK_DRIVE#stdio:}" bs=2048 skip="$2" count="$3" of="${disk_dk_dir}/got" 2>"${disk_dk_dir}/stat" || : >"${disk_dk_dir}/got"
  disk_discovery_pattern "$2" "$3" >"${disk_dk_dir}/want"
  disk_dk_seconds="$(awk '/copied, / { sub(/.*copied, /, ""); sub(/ s.*/, ""); print }' "${disk_dk_dir}/stat")"
  disk_dk_rate="$(disk_discovery_rate "$3" "${disk_dk_seconds}")"
  printf '%s,%s,%s,%s\n' "$2" "$3" "${disk_dk_seconds}" "${disk_dk_rate}" >>"${DISK_DISCOVERY_CSV}"
  disk_dk_bytes="$(disk_file_bytes "${disk_dk_dir}/got")"
  disk_dk_got=$((disk_dk_bytes / 2048))
  if cmp -s "${disk_dk_dir}/got" "${disk_dk_dir}/want"; then
    DISK_DISCOVERY_GOOD=$((DISK_DISCOVERY_GOOD + $3))
    return 0
  fi
  disk_discovery_first_bad "${disk_dk_dir}" "$2" "${disk_dk_got}"
}

disk_discovery_rate() {
  [ -n "$2" ] || return 0
  awk -v sectors="$1" -v seconds="$2" 'BEGIN { if (seconds > 0) printf "%.0f", sectors * 2 / seconds }'
}

disk_discovery_first_bad() {
  [ -z "${DISK_DISCOVERY_BAD}" ] || return 0
  disk_db_byte="$(cmp "$1/got" "$1/want" 2>&1 | awk '/EOF/ { exit } { for (i = 1; i < NF; i++) if ($i == "byte" || $i == "char") { v = $(i + 1); sub(/,$/, "", v); print v; exit } }')"
  if [ -n "${disk_db_byte}" ]; then
    DISK_DISCOVERY_BAD="$(($2 + (disk_db_byte - 1) / 2048)) differs"
    DISK_DISCOVERY_GOOD=$((DISK_DISCOVERY_GOOD + (disk_db_byte - 1) / 2048))
    return 0
  fi
  DISK_DISCOVERY_BAD="$(($2 + $3)) unreadable"
  DISK_DISCOVERY_GOOD=$((DISK_DISCOVERY_GOOD + $3))
}

disk_discovery_read() {
  disk_dr_dir="$(mktemp -d "${TMPDIR:-/tmp}/enban-discovery.XXXXXX")" || return 1
  mkdir -p "$(dirname "${DISK_DISCOVERY_CSV}")"
  printf 'sector,sectors,seconds,kib_per_second\n' >"${DISK_DISCOVERY_CSV}"
  disk_dr_chunk=$(((DISK_DISCOVERY_COUNT + 99) / 100))
  disk_dr_start=0
  DISK_DISCOVERY_GOOD=0
  DISK_DISCOVERY_BAD=""
  while [ "${disk_dr_start}" -lt "${DISK_DISCOVERY_COUNT}" ]; do
    disk_dr_count="${disk_dr_chunk}"
    [ $((disk_dr_start + disk_dr_count)) -le "${DISK_DISCOVERY_COUNT}" ] || disk_dr_count=$((DISK_DISCOVERY_COUNT - disk_dr_start))
    disk_discovery_chunk "${disk_dr_dir}" "${disk_dr_start}" "${disk_dr_count}"
    disk_dr_start=$((disk_dr_start + disk_dr_count))
  done
  rm -rf "${disk_dr_dir}"
}

disk_discovery_done() {
  disk_dd_verdict=good
  [ -z "${DISK_DISCOVERY_BAD}" ] || disk_dd_verdict=poor
  disk_dd_profile="$(disk_drive_short_profile)"
  disk_dd_folder="$(disk_discovery_folder)"
  mkdir -p "${disk_dd_folder}"
  disk_dd_when="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${disk_dd_when}" "${DISK_DRIVE}" "${disk_dd_profile}" "${DISK_DISCOVERY_COUNT}" "${DISK_WRITE_SPEED:-auto}" "${disk_dd_verdict}" "${DISK_DISCOVERY_CSV}" >>"${disk_dd_folder}/runs.tsv"
  printf 'Written      %s sectors\nRead back    %s of %s sectors\nCSV          %s\n' "${DISK_DISCOVERY_COUNT}" "${DISK_DISCOVERY_GOOD}" "${DISK_DISCOVERY_COUNT}" "${DISK_DISCOVERY_CSV}"
  disk_discovery_verdict
}

disk_discovery_verdict() {
  case "${DISK_DISCOVERY_BAD}" in
  *differs)
    disk_error "sector ${DISK_DISCOVERY_BAD% *} of the disc in ${DISK_DRIVE} does not read back as written."
    return 1
    ;;
  *unreadable)
    disk_error "sector ${DISK_DISCOVERY_BAD% *} of the disc in ${DISK_DRIVE} cannot be read."
    return 1
    ;;
  *) : ;;
  esac
  disk_dv_line="Done. ${DISK_DRIVE} passed discovery."
  if disk_ui_out; then
    disk_ui_done "${disk_dv_line}"
    return 0
  fi
  printf '%s\n' "${disk_dv_line}"
}

disk_discovery_go() {
  disk_discovery_write || return 1
  if [ "${DISK_WRITE_TEST}" = y ]; then
    disk_raw_done "Done. the test write of ${DISK_DISCOVERY_COUNT} sectors to ${DISK_DRIVE} ran to the end. nothing was written, so nothing was read back."
    return 0
  fi
  disk_discovery_read || return 1
  disk_discovery_done
}

disk_discovery_run() {
  disk_discovery_check || return 1
  disk_discovery_confirm || return 1
  disk_discovery_go
}
