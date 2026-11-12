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
  if [ "${DISK_SECTOR_RAW}" = y ]; then
    disk_raw_ready sector || return 1
  else
    disk_drive_read "${DISK_DRIVE}" sector || return 1
  fi
  DISK_SECTOR_FROM="${DISK_DRIVE#stdio:}"
  DISK_SECTOR_NAME="${DISK_DRIVE}"
}

disk_sector_size() {
  if [ "${DISK_SECTOR_RAW}" = y ]; then
    printf '2352\n'
    return 0
  fi
  printf '2048\n'
}

disk_sector_read() {
  disk_sr_size="$(disk_sector_size)"
  if [ "${DISK_SECTOR_RAW}" = y ] && [ -z "${DISK_SECTOR_IMAGE}" ]; then
    disk_sector_raw_read "$1" || return 1
  else
    disk_sector_plain "$1" "${disk_sr_size}" 2>/dev/null || : >"$1"
  fi
  disk_sector_sub_file "$1" || return 1
  disk_sr_bytes="$(disk_file_bytes "$1")"
  [ "${disk_sr_bytes}" -eq "${disk_sr_size}" ] && return 0
  disk_error "sector ${DISK_SECTOR_LBA} is past the end of ${DISK_SECTOR_NAME}."
  return 1
}

disk_sector_plain() {
  if [ -n "${DISK_SECTOR_IMAGE}" ]; then
    dd if="${DISK_SECTOR_FROM}" of="$1" bs="$2" skip="${DISK_SECTOR_LBA}" count=1
    return
  fi
  disk_drive_dd of="$1" bs="$2" skip="${DISK_SECTOR_LBA}" count=1
}

disk_sector_raw_read() {
  disk_sw_lba="$(printf '%08x' "${DISK_SECTOR_LBA}" | sed 's/../& /g')"
  if [ "${DISK_SECTOR_SUB}" = n ]; then
    # shellcheck disable=SC2086
    disk_raw_send -r 2352 -o "$1" "${DISK_SECTOR_FROM}" be 00 ${disk_sw_lba} 00 00 01 f8 00 00
    return
  fi
  # shellcheck disable=SC2086
  disk_raw_send -r 2448 -o "$1.both" "${DISK_SECTOR_FROM}" be 00 ${disk_sw_lba} 00 00 01 f8 01 00 || return 1
  dd if="$1.both" of="$1" bs=2352 count=1 2>/dev/null
  dd if="$1.both" of="$1.sub" bs=1 skip=2352 count=96 2>/dev/null
  rm -f "$1.both"
}

disk_sector_sub_file() {
  [ "${DISK_SECTOR_SUB}" = y ] && [ -n "${DISK_SECTOR_IMAGE}" ] || return 0
  disk_su_file="${DISK_SECTOR_IMAGE%.*}.sub"
  if [ ! -f "${disk_su_file}" ]; then
    disk_error "no subchannel file at ${disk_su_file}, where a CloneCD image keeps it."
    return 1
  fi
  dd if="${disk_su_file}" of="$1.sub" bs=96 skip="${DISK_SECTOR_LBA}" count=1 2>/dev/null || : >"$1.sub"
}

disk_sector_sub_show() {
  [ "${DISK_SECTOR_SUB}" = y ] || return 0
  printf '\nSubchannel P-W, 96 bytes\n'
  disk_sector_rows "$1.sub"
  od -An -tu1 -v -N 96 "$1.sub" 2>/dev/null | awk '
    { for (i = 1; i <= NF; i++) b[n++] = $i }
    END {
      for (k = 0; k < 12; k++) {
        q[k] = 0
        for (j = 0; j < 8; j++) q[k] = q[k] * 2 + int(b[k * 8 + j] / 64) % 2
      }
      if (q[0] % 16 != 1) { printf "Q channel    mode %d\n", q[0] % 16; exit }
      printf "Q channel    track %02x, index %02x, %02x:%02x:%02x in the track, %02x:%02x:%02x on the disc\n", q[1], q[2], q[3], q[4], q[5], q[7], q[8], q[9]
    }'
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
  disk_sh_kind="user data 2048"
  [ "${DISK_SECTOR_RAW}" = n ] || disk_sh_kind="raw 2352"
  printf 'LBA %s of %s, %s bytes\n' "${DISK_SECTOR_LBA}" "${DISK_SECTOR_NAME}" "${disk_sh_kind}"
  printf '%s\n' "offset  00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f  text"
  disk_sector_rows "$1"
  [ "${DISK_SECTOR_RAW}" = y ] || disk_sector_decode "$1"
  disk_sector_sub_show "$1"
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
  rm -f "${disk_sn_file}" "${disk_sn_file}.sub"
  return "${disk_sn_status}"
}
