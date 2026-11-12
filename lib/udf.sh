#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_udf_number() {
  od -An -tu1 -j "$1" -N "$2" "${DISK_LABEL_IMAGE}" 2>/dev/null | awk '{ for (i = NF; i >= 1; i--) value = value * 256 + $i } END { print value + 0 }'
}

disk_udf_octal() {
  printf '\\0%03o' "$@"
}

disk_udf_put() {
  printf '%b' "$2" | dd of="${DISK_LABEL_IMAGE}" bs=1 seek="$1" conv=notrunc 2>/dev/null
}

disk_udf_dstring() {
  disk_xd_text="$(printf '%s' "${DISK_LABEL_NAME}" | cut -c "1-$(($2 - 2))")"
  disk_xd_pad=$(($2 - 2 - ${#disk_xd_text}))
  {
    printf '\010%s' "${disk_xd_text}"
    head -c "${disk_xd_pad}" /dev/zero
    disk_xd_end="$(disk_udf_octal $((${#disk_xd_text} + 1)))"
    printf '%b' "${disk_xd_end}"
  } | dd of="${DISK_LABEL_IMAGE}" bs=1 seek="$1" conv=notrunc 2>/dev/null
}

disk_udf_crc() {
  od -An -tu1 -v -j $(($1 + 16)) -N "$2" "${DISK_LABEL_IMAGE}" 2>/dev/null | awk '
    function bits_xor(a, b,   result, bit) {
      result = 0
      bit = 1
      while (a > 0 || b > 0) {
        if (a % 2 != b % 2) result += bit
        a = int(a / 2)
        b = int(b / 2)
        bit *= 2
      }
      return result
    }
    { for (i = 1; i <= NF; i++) byte[n++] = $i }
    END {
      crc = 0
      for (i = 0; i < n; i++) {
        crc = bits_xor(crc, byte[i] * 256)
        for (k = 0; k < 8; k++) crc = (crc >= 32768 ? bits_xor(crc * 2 - 65536, 4129) : crc * 2)
      }
      print crc
    }'
}

disk_udf_seal() {
  disk_xs_length="$(disk_udf_number $(($1 + 10)) 2)"
  disk_xs_crc="$(disk_udf_crc "$1" "${disk_xs_length}")"
  case "${disk_xs_crc}" in
  '' | *[!0-9]*) return 1 ;;
  *) : ;;
  esac
  disk_xs_bytes="$(disk_udf_octal $((disk_xs_crc % 256)) $((disk_xs_crc / 256)))"
  disk_udf_put $(($1 + 8)) "${disk_xs_bytes}"
  disk_xs_sum="$(od -An -tu1 -N 16 -j "$1" "${DISK_LABEL_IMAGE}" | awk '{ for (i = 1; i <= NF; i++) if (i != 5) sum += $i } END { print sum % 256 }')"
  disk_xs_byte="$(disk_udf_octal "${disk_xs_sum}")"
  disk_udf_put $(($1 + 4)) "${disk_xs_byte}"
}

disk_udf_rename() {
  disk_udf_dstring $(($1 + $2)) "$3"
  disk_udf_seal "$1" || DISK_UDF_BROKEN=y
}

disk_udf_sequence() {
  disk_xq_at=$(($1 * 2048))
  disk_xq_end=$((disk_xq_at + $2))
  [ "${disk_xq_end}" -le $((disk_xq_at + 64 * 2048)) ] || disk_xq_end=$((disk_xq_at + 64 * 2048))
  while [ "${disk_xq_at}" -lt "${disk_xq_end}" ]; do
    disk_xq_tag="$(disk_udf_number "${disk_xq_at}" 2)"
    case "${disk_xq_tag}" in
    8) return 0 ;;
    *) disk_udf_descriptor "${disk_xq_tag}" "${disk_xq_at}" ;;
    esac
    disk_xq_at=$((disk_xq_at + 2048))
  done
}

disk_udf_descriptor() {
  case "$1" in
  1) disk_udf_rename "$2" 24 32 ;;
  4) disk_udf_info "$2" ;;
  5) DISK_UDF_START="$(disk_udf_number $(($2 + 188)) 4)" ;;
  6) disk_udf_logical "$2" ;;
  *) : ;;
  esac
}

disk_udf_info() {
  disk_xv_ident="$(disk_file_text "${DISK_LABEL_IMAGE}" $(($1 + 21)) 12)"
  [ "${disk_xv_ident}" = "*UDF LV Info" ] || return 0
  disk_udf_rename "$1" 116 128
}

disk_udf_logical() {
  disk_udf_rename "$1" 84 128
  DISK_UDF_BLOCK="$(disk_udf_number $(($1 + 212)) 4)"
  DISK_UDF_FSD="$(disk_udf_number $(($1 + 252)) 4)"
}

disk_udf_label() {
  DISK_UDF_BROKEN=n
  disk_xl_anchor=$((256 * 2048))
  disk_xl_tag="$(disk_udf_number "${disk_xl_anchor}" 2)"
  [ "${disk_xl_tag}" = 2 ] || return 1
  disk_xl_main="$(disk_udf_number $((disk_xl_anchor + 20)) 4)"
  disk_xl_main_length="$(disk_udf_number $((disk_xl_anchor + 16)) 4)"
  disk_xl_spare="$(disk_udf_number $((disk_xl_anchor + 28)) 4)"
  disk_xl_spare_length="$(disk_udf_number $((disk_xl_anchor + 24)) 4)"
  disk_udf_sequence "${disk_xl_main}" "${disk_xl_main_length}"
  disk_udf_sequence "${disk_xl_spare}" "${disk_xl_spare_length}"
  disk_xl_set=$((DISK_UDF_START * 2048 + DISK_UDF_FSD * DISK_UDF_BLOCK))
  disk_xl_kind="$(disk_udf_number "${disk_xl_set}" 2)"
  [ "${disk_xl_kind}" != 256 ] || disk_udf_rename "${disk_xl_set}" 112 128
  [ "${DISK_UDF_BROKEN}" = n ] || return 2
}
