#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_layer_keep() {
  [ -e "$1" ] || return 0
  disk_lk_name="$1.bak"
  disk_lk_count=1
  while [ -e "${disk_lk_name}" ] && [ "${disk_lk_count}" -le 99 ]; do
    disk_lk_name="$1.bak.${disk_lk_count}"
    disk_lk_count=$((disk_lk_count + 1))
  done
  if [ -e "${disk_lk_name}" ]; then
    disk_error "stopped: $1.bak to .bak.99 all exist, so there is no room to keep $1."
    return 1
  fi
  mv "$1" "${disk_lk_name}" || return 1
  disk_say "The earlier $1 is kept as ${disk_lk_name}."
}

disk_layer_dvd_file() {
  disk_ld_file="${DISK_LAYER_IMAGE%.*}.dvd"
  disk_layer_keep "${disk_ld_file}" || return 1
  printf 'LayerBreak=%s\r\n%s\r\n' "${DISK_LAYER_BREAK}" "${DISK_LAYER_IMAGE##*/}" >"${disk_ld_file}" || return 1
  disk_say "Wrote ${disk_ld_file}, which points ImgBurn and other burners at the layer break."
}

disk_layer_mds_bytes() {
  awk -v total="${DISK_LAYER_TOTAL}" -v zero="${DISK_LAYER_BREAK}" -v name="$1" '
    function u8(at, v) { b[at] = v % 256 }
    function le(at, v, width,   i) { for (i = 0; i < width; i++) { b[at + i] = v % 256; v = int(v / 256) } }
    function be(at, v, width,   i) { for (i = width - 1; i >= 0; i--) { b[at + i] = v % 256; v = int(v / 256) } }
    function text(at, s,   i) { for (i = 1; i <= length(s); i++) b[at + i - 1] = ord[substr(s, i, 1)] }
    function pfi(at,   last) {
      u8(at, 1)
      u8(at + 1, 15)
      u8(at + 2, 49)
      u8(at + 3, 16)
      be(at + 4, 196608, 4)
      last = 196608 + zero - 1
      be(at + 8, 16777215 - last + (total - zero) - 1, 4)
      be(at + 12, last, 4)
    }
    BEGIN {
      for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i
      size = 8408 + length(name) + 1
      for (i = 0; i < size; i++) b[i] = 0
      text(0, "MEDIA DESCRIPTOR")
      u8(16, 1)
      u8(17, 3)
      le(18, 16, 2)
      le(20, 1, 2)
      le(64, 88, 4)
      le(80, 8288, 4)
      pfi(88 + 4 + 2048)
      pfi(88 + 4100 + 4 + 2048)
      le(8288, 0, 4)
      le(8292, total, 4)
      le(8296, 1, 2)
      u8(8298, 1)
      le(8300, 1, 2)
      le(8302, 1, 2)
      le(8308, 8312, 4)
      u8(8312, 170)
      u8(8314, 20)
      u8(8316, 1)
      le(8324, total, 4)
      le(8328, 2048, 2)
      le(8360, 1, 4)
      le(8364, 8392, 4)
      le(8392, 8408, 4)
      text(8408, name)
      for (i = 0; i < size; i++) printf "\\0%03o", b[i]
    }'
}

disk_layer_mds_file() {
  disk_lm_file="${DISK_LAYER_IMAGE%.*}.mds"
  disk_layer_keep "${disk_lm_file}" || return 1
  disk_lm_bytes="$(disk_layer_mds_bytes "${DISK_LAYER_IMAGE##*/}")"
  printf '%b' "${disk_lm_bytes}" >"${disk_lm_file}" || return 1
  disk_say "Wrote ${disk_lm_file}, a dual-layer descriptor with the layer break, for burners that read MDS."
}

disk_layer_files() {
  [ "${DISK_LAYER_DVD}" = y ] || [ "${DISK_LAYER_MDS}" = y ] || return 0
  if [ -z "${DISK_LAYER_BREAK}" ]; then
    disk_error "--dvd-file and --mds-file need an image that spans two layers."
    return 1
  fi
  [ "${DISK_LAYER_DVD}" = n ] || disk_layer_dvd_file || return 1
  [ "${DISK_LAYER_MDS}" = n ] || disk_layer_mds_file
}
