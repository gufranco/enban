#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_layer_check() {
  if [ ! -f "${DISK_LAYER_IMAGE}" ]; then
    disk_error "no image at ${DISK_LAYER_IMAGE}."
    return 1
  fi
  if ! disk_iso_is "${DISK_LAYER_IMAGE}"; then
    disk_error "stopped: ${DISK_LAYER_IMAGE} is not an ISO image."
    return 1
  fi
  disk_kc_bytes="$(disk_file_bytes "${DISK_LAYER_IMAGE}")"
  DISK_LAYER_TOTAL=$((disk_kc_bytes / 2048))
  [ "${DISK_LAYER_TOTAL}" -gt $((DISK_LAYER_ZERO * 2)) ] || return 0
  disk_error "stopped: ${DISK_LAYER_IMAGE} is ${DISK_LAYER_TOTAL} sectors, more than a dual-layer DVD holds."
  return 1
}

disk_layer_ifos() {
  xorriso -indev "${DISK_LAYER_IMAGE}" -find /VIDEO_TS -type f -name 'VTS_*_0.IFO' -exec report_lba -- 2>/dev/null |
    sed -n "s/^File data lba: *0 , *\([0-9]*\) ,.*'\/VIDEO_TS\/\(VTS_[0-9]*\)_0.IFO'\$/\1 \2/p"
}

disk_layer_word() {
  od -An -tu1 -j "$1" -N 4 "${DISK_LAYER_IMAGE}" | awk '{ print $1 * 16777216 + $2 * 65536 + $3 * 256 + $4 }'
}

disk_layer_cells() {
  disk_kx_ifo=$(($1 * 2048))
  disk_kx_title="$(disk_layer_word $((disk_kx_ifo + 196)))"
  disk_kx_table="$(disk_layer_word $((disk_kx_ifo + 224)))"
  disk_kx_at=$((disk_kx_ifo + disk_kx_table * 2048))
  disk_kx_last="$(disk_layer_word $((disk_kx_at + 4)))"
  [ "${disk_kx_last}" -ge 19 ] || return 0
  od -An -tu1 -v -j $((disk_kx_at + 8)) -N "$((disk_kx_last - 7))" "${DISK_LAYER_IMAGE}" |
    awk -v base=$(($1 + disk_kx_title)) -v set="$2" '
      { for (i = 1; i <= NF; i++) b[n++] = $i }
      END {
        for (e = 0; e + 12 <= n; e += 12)
          print base + b[e + 4] * 16777216 + b[e + 5] * 65536 + b[e + 6] * 256 + b[e + 7], set
      }'
}

disk_layer_starts() {
  disk_layer_ifos | while read -r disk_ks_lba disk_ks_set; do
    disk_layer_cells "${disk_ks_lba}" "${disk_ks_set}"
  done
}

disk_layer_pick() {
  awk -v half=$(((DISK_LAYER_TOTAL + 1) / 2)) -v top="${DISK_LAYER_ZERO}" '
    $1 >= half && $1 <= top && (best == "" || $1 < best) { best = $1; set = $2 }
    END { if (best != "") print best, set; else print half, "-" }'
}

disk_layer_run() {
  disk_layer_check || return 1
  if [ "${DISK_LAYER_TOTAL}" -le "${DISK_LAYER_SINGLE}" ]; then
    printf '%s is %s sectors and fits on one layer, so it needs no layer break.\n' "${DISK_LAYER_IMAGE}" "${DISK_LAYER_TOTAL}"
    disk_layer_files
    return
  fi
  disk_kr_pick="$(disk_layer_starts | disk_layer_pick)"
  disk_kr_sector="${disk_kr_pick% *}"
  disk_kr_set="${disk_kr_pick#* }"
  DISK_LAYER_BREAK="${disk_kr_sector}"
  if [ "${disk_kr_set}" = - ]; then
    printf 'No cell starts between the middle and sector %s, so the layer break falls at sector %s, the middle.\n' "${DISK_LAYER_ZERO}" "${disk_kr_sector}"
  else
    printf 'Layer break at sector %s, a cell start in %s. layer 0 holds %s of %s sectors.\n' "${disk_kr_sector}" "${disk_kr_set}" "${disk_kr_sector}" "${DISK_LAYER_TOTAL}"
  fi
  disk_layer_files
}
