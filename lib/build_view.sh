#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_build_size() {
  awk -v k="$1" 'BEGIN {
    if (k < 1024) printf "%d KiB\n", k
    else if (k < 1048576) printf "%.1f MiB\n", k / 1024
    else printf "%.2f GiB\n", k / 1048576
  }'
}

disk_build_target() {
  if [ -z "${DISK_APP_DRIVE_NOTE}" ] && [ "${DISK_DRIVE_STATUS}" = blank ]; then
    disk_bt_name="$(disk_drive_short_profile)"
    printf '%s %s\n' $((DISK_DRIVE_FREE * 2)) "${disk_bt_name}"
    return 0
  fi
  printf '%s DVD-R\n' $((DISK_BUILD_DVD_SECTORS * 2))
}

disk_build_total() {
  printf '%s\n' "${DISK_APP_B_LAYOUT}" | awk -F "${DISK_TAB}" '{ k += $3; f += $4; d += $5 } END { print k + 0, f + 0, d + 0 }'
}

disk_frame_build() {
  disk_job_pane build && return 0
  disk_fb_count="$(disk_build_tab_count)"
  printf '%s\n' "Build image from files" "" "Disc layout"
  disk_build_rows
  printf '%s\n' "" "Capacity"
  disk_build_capacity
  printf '%s\n' "" "Output"
  disk_fb_names="$(disk_build_fs_names "${DISK_APP_B_FS}")"
  disk_job_row "${disk_fb_count}" "${DISK_APP_B_FOCUS}" "Type" "${disk_fb_names}"
  disk_fb_first="the first entry's name"
  disk_job_row $((disk_fb_count + 1)) "${DISK_APP_B_FOCUS}" "Label" "${DISK_APP_B_LABEL:-${disk_fb_first}}"
  disk_job_row $((disk_fb_count + 2)) "${DISK_APP_B_FOCUS}" "Image" "${DISK_APP_B_OUT:-none chosen, press Enter}"
  disk_fb_target="$(disk_build_target_text)"
  disk_job_row $((disk_fb_count + 3)) "${DISK_APP_B_FOCUS}" "Target" "${disk_fb_target}"
  disk_job_row $((disk_fb_count + 4)) "${DISK_APP_B_FOCUS}" "Publisher" "${DISK_APP_B_PUBLISHER:-none}"
  disk_job_row $((disk_fb_count + 5)) "${DISK_APP_B_FOCUS}" "Date" "${DISK_APP_B_DATE:-when it is built}"
  disk_job_row $((disk_fb_count + 6)) "${DISK_APP_B_FOCUS}" "Boot" "${DISK_APP_B_BOOT:-not bootable}"
  disk_job_row $((disk_fb_count + 7)) "${DISK_APP_B_FOCUS}" "Emulation" "${DISK_APP_B_EMULATION}"
  disk_job_row $((disk_fb_count + 8)) "${DISK_APP_B_FOCUS}" "Platform" "${DISK_APP_B_PLATFORM}"
  printf '%s\n' "" "a file   f folder   x remove   n rename   b build"
}

disk_build_target_text() {
  if [ "${DISK_APP_B_TARGET}" = image ]; then
    printf 'an image file\n'
    return 0
  fi
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    printf 'the disc in the drive\n'
    return 0
  fi
  printf 'the disc in %s\n' "${DISK_DRIVE}"
}

disk_build_rows() {
  if [ -z "${DISK_APP_B_LAYOUT}" ]; then
    printf '%s\n' "  Nothing yet. Press a to add a file or f to add a folder."
    return 0
  fi
  disk_bw_total="$(disk_build_total)"
  disk_bw_size="$(disk_build_size "${disk_bw_total%% *}")"
  disk_bw_rest="${disk_bw_total#* }"
  printf '  /  %s, %s files, %s folders\n' "${disk_bw_size}" "${disk_bw_rest% *}" "${disk_bw_rest#* }"
  printf '%s\n' "${DISK_APP_B_LAYOUT}" | awk -F "${DISK_TAB}" -v focus="${DISK_APP_B_FOCUS}" '
    function size(k) { return k < 1024 ? sprintf("%d KiB", k) : (k < 1048576 ? sprintf("%.1f MiB", k / 1024) : sprintf("%.2f GiB", k / 1048576)) }
    {
      kind = ($5 > 0 ? "folder" : "file")
      name = $1 (kind == "folder" ? "/" : "")
      printf "%s%-32s %10s  %s\n", (NR - 1 == focus ? "> " : "  "), name, size($3), kind
    }'
}

disk_build_capacity() {
  disk_bc_target="$(disk_build_target)"
  disk_bc_total="$(disk_build_total)"
  printf '%s %s\n' "${disk_bc_total%% *}" "${disk_bc_target}" | awk '
    function size(k) { return k < 1024 ? sprintf("%d KiB", k) : (k < 1048576 ? sprintf("%.1f MiB", k / 1024) : sprintf("%.2f GiB", k / 1048576)) }
    {
      used = $1; room = $2; name = $3
      pct = (room > 0 ? int(used * 100 / room) : 100)
      fill = (pct > 100 ? 30 : int(pct * 30 / 100))
      bar = ""
      for (i = 0; i < 30; i++) bar = bar (i < fill ? "#" : "-")
      printf "  [%s] %d%%\n", bar, pct
      printf "  %s of %s on %s.\n", size(used), size(room), name
    }'
}

disk_build_fs_names() {
  printf '%s\n' "$1" | awk -F ',' '{
    out = ""
    for (i = 1; i <= NF; i++) {
      name = ($i == "iso9660" ? "ISO9660" : ($i == "joliet" ? "Joliet" : "UDF"))
      out = out (i > 1 ? ", " : "") name
    }
    print out
  }'
}

disk_build_tab_refresh() {
  DISK_APP_B_SIDE="$(disk_build_side)"
}

disk_build_side() {
  disk_bs_names="$(disk_build_fs_names "${DISK_APP_B_FS}")"
  disk_bs_label="$(disk_build_side_label)"
  printf '%s\n' "File system"
  printf 'Type         %s\n' "${disk_bs_names}"
  printf 'Label        %s\n' "${disk_bs_label}"
  printf '%s\n' "" "Checks"
  disk_build_checks
  printf '%s\n' "" "Detected"
  disk_bs_content="$(disk_build_content)"
  printf 'Content      %s\n' "${disk_bs_content}"
}

disk_build_side_label() {
  disk_bl_first="${DISK_APP_B_LAYOUT%%"${DISK_TAB}"*}"
  disk_bl_text="${DISK_APP_B_LABEL:-${disk_bl_first}}"
  [ -n "${disk_bl_text}" ] || {
    printf 'none yet\n'
    return 0
  }
  printf '%s' "${disk_bl_text}" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9_' '_'
  printf '\n'
}

disk_build_checks() {
  if [ -z "${DISK_APP_B_LAYOUT}" ]; then
    printf '%s\n' "Nothing to check yet."
    return 0
  fi
  disk_build_check_room
  disk_build_check_names
}

disk_build_check_room() {
  disk_bo_target="$(disk_build_target)"
  disk_bo_total="$(disk_build_total)"
  disk_bo_name="${disk_bo_target#* }"
  if [ "${disk_bo_total%% *}" -le "${disk_bo_target%% *}" ]; then
    printf 'ok     fits on %s\n' "${disk_bo_name}"
    return 0
  fi
  printf 'error  too large for %s\n' "${disk_bo_name}"
}

disk_build_check_names() {
  disk_bn_long="$(disk_build_names_list | disk_build_count_long)"
  disk_bn_kept="$(disk_build_kept)"
  case "${disk_bn_long}" in
  0) printf 'ok     every name fits ISO9660 level 1\n' ;;
  1) printf 'warn   1 name is too long for ISO9660 level 1; %s\n' "${disk_bn_kept}" ;;
  *) printf 'warn   %s names are too long for ISO9660 level 1; %s\n' "${disk_bn_long}" "${disk_bn_kept}" ;;
  esac
}

disk_build_names_list() {
  printf '%s\n' "${DISK_APP_B_LAYOUT}" | cut -f 1
  printf '%s\n' "${DISK_APP_B_LAYOUT}" | cut -f 2 | disk_build_inner_names
}

disk_build_inner_names() {
  while IFS= read -r disk_bi_source; do
    find "${disk_bi_source}" -mindepth 1 | sed 's|.*/||'
  done
}

disk_build_count_long() {
  awk -F '.' '{
    base = $1; ext = (NF > 1 ? $2 : "")
    fits = (NF <= 2 && base ~ /^[A-Za-z0-9_]+$/ && length(base) <= 8 && ext ~ /^[A-Za-z0-9_]*$/ && length(ext) <= 3)
    if (!fits) n++
  } END { print n + 0 }'
}

disk_build_kept() {
  case "${DISK_APP_B_FS}" in
  iso9660) printf 'ISO9660 shortens it\n' ;;
  *) printf 'Joliet or UDF keeps the full name\n' ;;
  esac
}

disk_build_content() {
  disk_bt_names="$(printf '%s\n' "${DISK_APP_B_LAYOUT}" | cut -f 1)"
  if printf '%s\n' "${disk_bt_names}" | grep -qx VIDEO_TS; then
    printf 'DVD Video\n'
    return 0
  fi
  if printf '%s\n' "${disk_bt_names}" | grep -qx BDMV; then
    printf 'Blu-ray movie\n'
    return 0
  fi
  printf 'data\n'
}
