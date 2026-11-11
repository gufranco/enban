#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_sector_source() {
  if [ -n "${DISK_SECTOR_IMAGE}" ]; then
    if [ ! -f "${DISK_SECTOR_IMAGE}" ]; then
      disk_error "no image at ${DISK_SECTOR_IMAGE}."
      return 1
    fi
    DISK_SECTOR_FROM="${DISK_SECTOR_IMAGE}"
    DISK_SECTOR_NAME="${DISK_SECTOR_IMAGE}"
    return 0
  fi
  disk_drive_read "${DISK_DRIVE}" sector || return 1
  DISK_SECTOR_FROM="${DISK_DRIVE#stdio:}"
  DISK_SECTOR_NAME="${DISK_DRIVE}"
}

disk_sector_read() {
  dd if="${DISK_SECTOR_FROM}" of="$1" bs=2048 skip="${DISK_SECTOR_LBA}" count=1 2>/dev/null || : >"$1"
  disk_sr_bytes="$(wc -c <"$1" | tr -d '[:space:]')"
  [ "${disk_sr_bytes}" -eq 2048 ] && return 0
  disk_error "sector ${DISK_SECTOR_LBA} is past the end of ${DISK_SECTOR_NAME}."
  return 1
}

disk_sector_rows() {
  od -An -tx1 -v "$1" | awk '
    BEGIN { hex = "0123456789abcdef" }
    NF {
      text = ""
      for (i = 1; i <= NF; i++) {
        n = (index(hex, substr($i, 1, 1)) - 1) * 16 + index(hex, substr($i, 2, 1)) - 1
        text = text (n >= 32 && n < 127 ? sprintf("%c", n) : ".")
      }
      printf "%04x    %s %s %s %s %s %s %s %s  %s %s %s %s %s %s %s %s  %s\n", row * 16, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, text
      row++
    }'
}

disk_sector_decode() {
  od -An -tu1 -v -N 148 "$1" | awk '
    { for (i = 1; i <= NF; i++) b[count++] = $i }
    function le(at) { return b[at] + b[at + 1] * 256 + b[at + 2] * 65536 + b[at + 3] * 16777216 }
    END {
      id = sprintf("%c%c%c%c%c", b[1], b[2], b[3], b[4], b[5])
      if (b[0] != 1 || id != "CD001") exit
      volume = ""
      for (i = 40; i < 72; i++) volume = volume (b[i] >= 32 && b[i] < 127 ? sprintf("%c", b[i]) : " ")
      sub(/ +$/, "", volume)
      printf "\nDecoded\nIdentifier   CD001, version %d\nVolume       %s\n", b[6], volume
      printf "Volume size  %d blocks of 2048\nPath table   %d bytes at LBA %d\n", le(80), le(132), le(140)
    }'
}

disk_sector_show() {
  printf 'LBA %s of %s, user data 2048 bytes\n' "${DISK_SECTOR_LBA}" "${DISK_SECTOR_NAME}"
  printf '%s\n' "offset  00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f  text"
  disk_sector_rows "$1"
  disk_sector_decode "$1"
}

disk_sector_run() {
  disk_sector_source || return 1
  disk_sn_file="$(mktemp "${TMPDIR:-/tmp}/enban-sector.XXXXXX")" || return 1
  disk_sn_status=0
  if disk_sector_read "${disk_sn_file}"; then
    disk_sector_show "${disk_sn_file}"
  else
    disk_sn_status=1
  fi
  rm -f "${disk_sn_file}"
  return "${disk_sn_status}"
}
