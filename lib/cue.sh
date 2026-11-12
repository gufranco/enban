#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_cue_wav() {
  od -An -tu1 -v -N 4096 "$1" | awk '
    { for (i = 1; i <= NF; i++) b[n++] = $i }
    function le(at, size,   v, i) { v = 0; for (i = size - 1; i >= 0; i--) v = v * 256 + b[at + i]; return v }
    function tag(at) { return sprintf("%c%c%c%c", b[at], b[at + 1], b[at + 2], b[at + 3]) }
    END {
      if (n < 12 || tag(0) != "RIFF" || tag(8) != "WAVE") exit
      at = 12
      for (step = 0; step < 64 && at + 8 <= n; step++) {
        size = le(at + 4, 4)
        if (tag(at) == "fmt ") { channels = le(at + 10, 2); rate = le(at + 12, 4); bits = le(at + 22, 2) }
        if (tag(at) == "data") { print rate + 0, bits + 0, channels + 0, size; exit }
        at += 8 + size + size % 2
      }
    }'
}

disk_cue_track() {
  if [ ! -f "$1" ]; then
    disk_error "no file at $1."
    return 1
  fi
  disk_ct_shape="$(disk_cue_wav "$1")"
  if [ -z "${disk_ct_shape}" ]; then
    disk_error "$1 is not a WAV file."
    return 1
  fi
  disk_ct_rate="${disk_ct_shape%% *}"
  disk_ct_rest="${disk_ct_shape#* }"
  disk_ct_bits="${disk_ct_rest%% *}"
  disk_ct_rest="${disk_ct_rest#* }"
  disk_ct_channels="${disk_ct_rest%% *}"
  if [ "${disk_ct_rate}:${disk_ct_bits}:${disk_ct_channels}" != 44100:16:2 ]; then
    disk_error "$1 is ${disk_ct_rate} Hz, ${disk_ct_bits}-bit, ${disk_ct_channels} channels; an audio CD needs 44100 Hz, 16-bit, 2 channels."
    return 1
  fi
  disk_ct_bytes="${disk_ct_shape##* }"
  DISK_CUE_SECTORS=$(((disk_ct_bytes + 2351) / 2352))
}

disk_cue_check() {
  disk_ck_folder="$(dirname "${DISK_CUE_OUT}")"
  if [ ! -d "${disk_ck_folder}" ]; then
    disk_error "no folder at ${disk_ck_folder}."
    return 1
  fi
  if [ -e "${DISK_CUE_OUT}" ]; then
    disk_error "stopped: ${DISK_CUE_OUT} already exists."
    return 1
  fi
  case "${DISK_CUE_TITLE}${DISK_CUE_PERFORMER}" in
  *'"'*)
    disk_error "--title and --performer cannot hold a double quote."
    return 1
    ;;
  *) : ;;
  esac
  case "${DISK_CUE_PREGAP}" in
  '' | *[!0-9]*)
    disk_error "--pregap must be a whole number of seconds, got: ${DISK_CUE_PREGAP}"
    return 1
    ;;
  *)
    disk_cue_decode || return 1
    disk_cue_measure
    ;;
  esac
}

disk_cue_measure() {
  DISK_CUE_TOTAL=0
  disk_cm_count="$(printf '%s\n' "${DISK_CUE_TRACKS}" | grep -c '')"
  disk_cm_index=1
  while [ "${disk_cm_index}" -le "${disk_cm_count}" ]; do
    disk_cm_track="$(printf '%s\n' "${DISK_CUE_TRACKS}" | sed -n "${disk_cm_index}p")"
    disk_cue_track "${disk_cm_track}" || return 1
    DISK_CUE_TOTAL=$((DISK_CUE_TOTAL + DISK_CUE_SECTORS))
    [ "${disk_cm_index}" -eq 1 ] || DISK_CUE_TOTAL=$((DISK_CUE_TOTAL + DISK_CUE_PREGAP * 75))
    disk_cm_index=$((disk_cm_index + 1))
  done
  [ "${DISK_CUE_TOTAL}" -le 360000 ] && return 0
  disk_cm_length="$(disk_cue_length "${DISK_CUE_TOTAL}")"
  disk_error "the tracks run ${disk_cm_length}, longer than the 80:00 a CD-R holds."
  return 1
}

disk_cue_length() {
  disk_cl_seconds=$(($1 / 75))
  printf '%02d:%02d\n' $((disk_cl_seconds / 60)) $((disk_cl_seconds % 60))
}

disk_cue_sheet() {
  disk_cs_home="$(cd "$(dirname "${DISK_CUE_OUT}")" && pwd)"
  [ -z "${DISK_CUE_TITLE}" ] || printf 'TITLE "%s"\n' "${DISK_CUE_TITLE}"
  [ -z "${DISK_CUE_PERFORMER}" ] || printf 'PERFORMER "%s"\n' "${DISK_CUE_PERFORMER}"
  printf '%s\n' "${DISK_CUE_TRACKS}" | awk -v home="${disk_cs_home}" -v gap="${DISK_CUE_PREGAP}" '
    {
      path = $0
      folder = path; sub(/\/[^\/]*$/, "", folder)
      name = path; sub(/.*\//, "", name)
      shown = (folder == home ? name : path)
      title = name; sub(/\.[^.]*$/, "", title)
      printf "FILE \"%s\" WAVE\n  TRACK %02d AUDIO\n    TITLE \"%s\"\n", shown, NR, title
      if (NR > 1 && gap > 0) printf "    PREGAP %02d:%02d:00\n", int(gap / 60), gap % 60
      print "    INDEX 01 00:00:00"
    }'
}

disk_cue_done() {
  disk_cd_count="$(printf '%s\n' "${DISK_CUE_TRACKS}" | grep -c '')"
  disk_cd_length="$(disk_cue_length "${DISK_CUE_TOTAL}")"
  printf 'Tracks       %s\nLength       %s\n' "${disk_cd_count}" "${disk_cd_length}"
  disk_cd_noun="$(disk_queue_plural "${disk_cd_count}" track)"
  disk_cd_line="Done. ${DISK_CUE_OUT} lists ${disk_cd_noun}."
  if disk_ui_out; then
    disk_ui_done "${disk_cd_line}"
    return 0
  fi
  printf '%s\n' "${disk_cd_line}"
}

disk_cue_run() {
  if ! disk_cue_check || ! disk_cue_sheet >"${DISK_CUE_OUT}"; then
    disk_cue_undo
    return 1
  fi
  disk_cue_done
}
