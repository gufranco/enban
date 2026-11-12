#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_discovery_tab_key() {
  disk_job_key discovery "$1" && return 0
  case "$1" in
  up) DISK_APP_D_FIELD=0 ;;
  down) DISK_APP_D_FIELD=1 ;;
  enter) disk_discovery_tab_edit ;;
  t) disk_discovery_tab_start ;;
  *) return 0 ;;
  esac
}

disk_discovery_tab_edit() {
  if [ "${DISK_APP_D_FIELD}" -eq 0 ]; then
    disk_app_ask "Sectors to write, empty for all free" "all free"
    case "${DISK_APP_ANSWER}" in
    '') DISK_APP_D_SECTORS="" ;;
    *[!0-9]* | 0*) DISK_APP_STATUS="The sectors must be a whole number from 1, or empty for all free." ;;
    *) DISK_APP_D_SECTORS="${DISK_APP_ANSWER}" ;;
    esac
    return 0
  fi
  disk_app_ask "Write speed, empty for the drive's choice" "8"
  case "${DISK_APP_ANSWER}" in
  *[!0-9]*) DISK_APP_STATUS="The speed must be a whole number, such as 8." ;;
  *) DISK_APP_D_SPEED="${DISK_APP_ANSWER}" ;;
  esac
}

disk_discovery_tab_start() {
  disk_job_busy && return 0
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    DISK_APP_STATUS="There is no drive to test."
    return 0
  fi
  disk_dt_name="$(disk_drive_word "${DISK_DRIVE}")"
  disk_app_ask "Type ${disk_dt_name} to fill the disc with test data, or anything else to stop" "${disk_dt_name}"
  if [ "${DISK_APP_ANSWER}" != "${disk_dt_name}" ]; then
    DISK_APP_STATUS="Nothing was written."
    return 0
  fi
  disk_job_launch disk_discovery_tab_steps discovery "the disc in ${DISK_DRIVE}"
}

disk_discovery_tab_steps() {
  DISK_DISCOVERY_SECTORS="${DISK_APP_D_SECTORS}"
  DISK_WRITE_SPEED="${DISK_APP_D_SPEED}"
  DISK_DISCOVERY_CSV=""
  disk_discovery_check || return 1
  disk_discovery_go
}

disk_frame_discovery() {
  disk_job_pane discovery && return 0
  disk_fd_sectors="${DISK_APP_D_SECTORS:-all free}"
  disk_fd_speed="chosen by the drive"
  [ -z "${DISK_APP_D_SPEED}" ] || disk_fd_speed="${DISK_APP_D_SPEED}x"
  printf '%s\n' "Discovery" "" "Writes test data to a blank disc and reads it back, to judge a drive and media pair before trusting it with real data." ""
  disk_job_row 0 "${DISK_APP_D_FIELD}" "Sectors" "${disk_fd_sectors}"
  disk_job_row 1 "${DISK_APP_D_FIELD}" "Speed" "${disk_fd_speed}"
  printf '\n'
  disk_discovery_last
  printf '%s\n' "" "enter edit   t start test"
}

disk_discovery_last() {
  disk_dl_runs="$(disk_discovery_folder)/runs.tsv"
  if [ ! -s "${disk_dl_runs}" ]; then
    printf '%s\n' "No runs yet."
    return 0
  fi
  sed -n '$p' "${disk_dl_runs}" | awk -F '\t' '{ printf "Last run, %s on %s at %s: %s\n", $3, $2, ($5 == "auto" ? "auto" : $5 "x"), $6 }'
  disk_dl_csv="$(sed -n '$p' "${disk_dl_runs}" | cut -f 7)"
  disk_discovery_graph "${disk_dl_csv}"
  printf '%s\n' "" "Compare"
  printf '%-12s %-8s %-6s %-9s %s\n' Date Media Speed Sectors Verdict
  awk -F '\t' '{ row[NR] = $0 } END { for (i = NR; i > 0 && i > NR - 5; i--) { split(row[i], f, "\t"); printf "%-12s %-8s %-6s %-9s %s\n", substr(f[1], 1, 10), f[3], (f[5] == "auto" ? "auto" : f[5] "x"), f[4], f[6] } }' "${disk_dl_runs}"
}

disk_discovery_graph() {
  if [ -z "$1" ] || [ ! -f "$1" ]; then
    printf '%s\n' "The read rate of this run was not saved."
    return 0
  fi
  awk -F , '
    BEGIN { split("\342\226\201 \342\226\202 \342\226\203 \342\226\204 \342\226\205 \342\226\206 \342\226\207 \342\226\210", bar, " ") }
    NR > 1 && $4 != "" { rate[++n] = $4 + 0; if (rate[n] > high) high = rate[n]; if (low == "" || rate[n] < low) low = rate[n] }
    END {
      if (n == 0 || high == 0) { print "This system gave no timing for this run."; exit }
      step = (n > 50 ? n / 50 : 1)
      line = ""
      for (i = 1; i <= n; i += step) { level = int(rate[int(i)] * 8 / high + 0.5); if (level < 1) level = 1; line = line bar[level] }
      printf "Read rate  %s  %d to %d KiB/s\n", line, low, high
    }' "$1"
}
