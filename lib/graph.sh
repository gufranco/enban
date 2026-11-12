#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_graph_unit() {
  case "${DISK_DRIVE_CODE}" in
  0008 | 0009 | 000a | 0020 | 0021 | 0022) printf '150\n' ;;
  004* | 005*) printf '4500\n' ;;
  *) printf '1353\n' ;;
  esac
}

disk_graph_ibg() {
  disk_gi_unit="$(disk_graph_unit)"
  disk_gi_date="$(date -u '+%m/%d/%Y %H:%M:%S')"
  awk -F ',' -v unit="${disk_gi_unit}" -v date="${disk_gi_date}" -v drive="${DISK_DRIVE}" \
    -v vendor="${DISK_DRIVE_VENDOR}" -v product="${DISK_DRIVE_PRODUCT}" -v firmware="${DISK_DRIVE_REVISION}" \
    -v media="${DISK_DRIVE_PROFILE}" -v media_id="${DISK_DRIVE_MEDIA_ID:-N/A}" -v sectors="${DISK_DISCOVERY_COUNT}" '
    NR == 1 { next }
    {
      speed = $4 / unit
      if (rows == 0) first = speed
      last = speed
      if (speed > top) top = speed
      seconds += $3
      done += $2
      row[++rows] = sprintf("%.2f,%d,%.0f,0", speed, $1, $3 * 1000)
    }
    END {
      average = (seconds > 0 ? done * 2 / seconds / unit : 0)
      printf "IBGD\r\n\r\n[START_CONFIGURATION]\r\nIBGD_VERSION=2\r\n\r\nDATE=%s\r\n\r\nSAMPLE_RATE=100\r\n\r\n", date
      printf "DEVICE=[0:0:0] %s %s %s (%s) (Unknown)\r\nDEVICE_ADDRESS=0:0:0\r\n", vendor, product, firmware, drive
      printf "DEVICE_MAKEMODEL=%s %s\r\nDEVICE_FIRMWAREVERSION=%s\r\nDEVICE_DRIVELETTER=%s\r\nDEVICE_BUSTYPE=Unknown\r\n\r\n", vendor, product, firmware, drive
      printf "MEDIA_TYPE=%s\r\nMEDIA_BOOKTYPE=Unknown\r\nMEDIA_ID=%s\r\nMEDIA_TRACKPATH=PTP\r\nMEDIA_SPEEDS=N/A\r\n", media, media_id
      printf "MEDIA_CAPACITY=%d\r\nMEDIA_LAYER_BREAK=0\r\n\r\n", sectors
      printf "DATA_IMAGEFILE=/dev/null\r\nDATA_SECTORS=%d\r\nDATA_TYPE=MODE1/2048\r\nDATA_VOLUMEIDENTIFIER=\r\n\r\n", sectors
      printf "VERIFY_SPEED_START=%.2f\r\nVERIFY_SPEED_END=%.2f\r\nVERIFY_SPEED_AVERAGE=%.2f\r\n", first, last, average
      printf "VERIFY_SPEED_MAX=%.2f\r\nVERIFY_TIME_TAKEN=%d\r\n[END_CONFIGURATION]\r\n\r\nHRPC=True\r\n\r\n", top, seconds
      printf "[START_VERIFY_GRAPH_VALUES]\r\n"
      for (i = 1; i <= rows; i++) printf "%s\r\n", row[i]
      printf "[END_VERIFY_GRAPH_VALUES]\r\n\r\n"
    }' "$1" >"$2"
}
