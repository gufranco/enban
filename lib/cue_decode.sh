#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_cue_compressed() {
  case "$1" in
  *.[fF][lL][aA][cC] | *.[mM][pP]3 | *.[oO][gG][gG] | *.[oO][gG][aA] | *.[oO][pP][uU][sS] | *.[mM]4[aA] | *.[aA][aA][cC] | *.[wW][mM][aA] | *.[aA][pP][eE] | *.[wW][vV] | *.[aA][iI][fF] | *.[aA][iI][fF][fF] | *.[mM][pP][cC]) return 0 ;;
  *) return 1 ;;
  esac
}

disk_cue_decode_one() {
  disk_cz_name="${1##*/}"
  disk_cz_out="$(printf '%s/%02d %s.wav' "${DISK_CUE_DECODED}" "$2" "${disk_cz_name%.*}")"
  if ! ffmpeg -nostdin -v error -i "$1" -ar 44100 -ac 2 -c:a pcm_s16le "${disk_cz_out}" 2>/dev/null; then
    disk_error "ffmpeg could not decode $1."
    return 1
  fi
  printf '%s\n' "${disk_cz_out}"
}

disk_cue_decode_ready() {
  if ! command -v ffmpeg >/dev/null 2>&1; then
    disk_error "cue needs ffmpeg to turn FLAC, MP3, OGG, M4A and the like into CD audio. install it and try again."
    return 1
  fi
  disk_cy_folder="${DISK_CUE_OUT%.*} tracks"
  if [ -e "${disk_cy_folder}" ]; then
    disk_error "stopped: ${disk_cy_folder} already exists."
    return 1
  fi
  mkdir "${disk_cy_folder}" || return 1
  DISK_CUE_DECODED="${disk_cy_folder}"
}

disk_cue_decode() {
  DISK_CUE_DECODED=""
  disk_cx_count="$(printf '%s\n' "${DISK_CUE_TRACKS}" | grep -c '')"
  disk_cx_wanted=n
  disk_cx_index=1
  while [ "${disk_cx_index}" -le "${disk_cx_count}" ]; do
    disk_cx_track="$(printf '%s\n' "${DISK_CUE_TRACKS}" | sed -n "${disk_cx_index}p")"
    ! disk_cue_compressed "${disk_cx_track}" || disk_cx_wanted=y
    disk_cx_index=$((disk_cx_index + 1))
  done
  [ "${disk_cx_wanted}" = y ] || return 0
  disk_cue_decode_ready || return 1
  disk_say "Decoding the compressed tracks into ${DISK_CUE_DECODED} with ffmpeg."
  disk_cue_decode_all "${disk_cx_count}"
}

disk_cue_decode_all() {
  disk_cw_list=""
  disk_cw_index=1
  while [ "${disk_cw_index}" -le "$1" ]; do
    disk_cw_track="$(printf '%s\n' "${DISK_CUE_TRACKS}" | sed -n "${disk_cw_index}p")"
    if disk_cue_compressed "${disk_cw_track}"; then
      disk_cw_track="$(disk_cue_decode_one "${disk_cw_track}" "${disk_cw_index}")" || return 1
    fi
    disk_cw_list="${disk_cw_list}${disk_cw_list:+${DISK_NEWLINE}}${disk_cw_track}"
    disk_cw_index=$((disk_cw_index + 1))
  done
  DISK_CUE_TRACKS="${disk_cw_list}"
}

disk_cue_undo() {
  [ -z "${DISK_CUE_DECODED}" ] || rm -rf "${DISK_CUE_DECODED}"
  DISK_CUE_DECODED=""
}
