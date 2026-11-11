#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_build_tab_key() {
  disk_job_key build "$1" && return 0
  disk_bk_count="$(disk_build_tab_count)"
  case "$1" in
  up) [ "${DISK_APP_B_FOCUS}" -le 0 ] || DISK_APP_B_FOCUS=$((DISK_APP_B_FOCUS - 1)) ;;
  down) [ "${DISK_APP_B_FOCUS}" -ge $((disk_bk_count + 3)) ] || DISK_APP_B_FOCUS=$((DISK_APP_B_FOCUS + 1)) ;;
  a) disk_build_tab_add file ;;
  f) disk_build_tab_add folder ;;
  x) disk_build_tab_remove "${disk_bk_count}" ;;
  n) disk_build_tab_rename "${disk_bk_count}" ;;
  enter) disk_build_tab_edit $((DISK_APP_B_FOCUS - disk_bk_count)) ;;
  b) disk_build_tab_start ;;
  *) return 0 ;;
  esac
}

disk_build_tab_count() {
  [ -n "${DISK_APP_B_LAYOUT}" ] || {
    printf '0\n'
    return 0
  }
  printf '%s\n' "${DISK_APP_B_LAYOUT}" | wc -l | tr -d '[:space:]'
}

disk_build_tab_add() {
  disk_ba_noun="$(disk_build_tab_noun "$1")"
  disk_app_ask "${disk_ba_noun} to add" "path to a $1"
  [ -n "${DISK_APP_ANSWER}" ] || return 0
  disk_ba_path="${DISK_APP_ANSWER%/}"
  if ! disk_build_tab_is "$1" "${disk_ba_path}"; then
    DISK_APP_STATUS="No $1 at ${DISK_APP_ANSWER}."
    return 0
  fi
  disk_ba_name="${disk_ba_path##*/}"
  disk_build_tab_free "${disk_ba_name}" || return 0
  disk_ba_row="$(disk_build_tab_row "${disk_ba_name}" "${disk_ba_path}")"
  DISK_APP_B_FOCUS="$(disk_build_tab_count)"
  DISK_APP_B_LAYOUT="$(printf '%s\n%s\n' "${DISK_APP_B_LAYOUT}" "${disk_ba_row}" | sed '/^$/d')"
  disk_build_tab_refresh
  DISK_APP_STATUS="Added ${disk_ba_name}."
}

disk_build_tab_noun() {
  case "$1" in
  file) printf 'File\n' ;;
  *) printf 'Folder\n' ;;
  esac
}

disk_build_tab_is() {
  case "$1" in
  file) [ -f "$2" ] ;;
  *) [ -d "$2" ] ;;
  esac
}

disk_build_tab_free() {
  disk_bf_taken="$(printf '%s\n' "${DISK_APP_B_LAYOUT}" | cut -f 1 | grep -cxF -- "$1" || true)"
  [ "${disk_bf_taken}" -eq 0 ] && return 0
  DISK_APP_STATUS="$1 is already on the disc. Rename it first with n."
  return 1
}

disk_build_tab_row() {
  disk_br_kib="$(du -sk "$2" | cut -f 1)"
  disk_br_files="$(find "$2" -type f | wc -l | tr -d '[:space:]')"
  disk_br_folders="$(find "$2" -type d | wc -l | tr -d '[:space:]')"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "${disk_br_kib}" "${disk_br_files}" "${disk_br_folders}"
}

disk_build_tab_remove() {
  [ "${DISK_APP_B_FOCUS}" -lt "$1" ] || return 0
  disk_bx_line=$((DISK_APP_B_FOCUS + 1))
  disk_bx_name="$(printf '%s\n' "${DISK_APP_B_LAYOUT}" | sed -n "${disk_bx_line}p" | cut -f 1)"
  DISK_APP_B_LAYOUT="$(printf '%s\n' "${DISK_APP_B_LAYOUT}" | sed "${disk_bx_line}d")"
  [ "${DISK_APP_B_FOCUS}" -lt $(($1 - 1)) ] || [ "${DISK_APP_B_FOCUS}" -eq 0 ] || DISK_APP_B_FOCUS=$((DISK_APP_B_FOCUS - 1))
  disk_build_tab_refresh
  DISK_APP_STATUS="Removed ${disk_bx_name}."
}

disk_build_tab_rename() {
  [ "${DISK_APP_B_FOCUS}" -lt "$1" ] || return 0
  disk_bn_line=$((DISK_APP_B_FOCUS + 1))
  disk_bn_old="$(printf '%s\n' "${DISK_APP_B_LAYOUT}" | sed -n "${disk_bn_line}p" | cut -f 1)"
  disk_app_ask "New name for ${disk_bn_old}" "${disk_bn_old}"
  disk_build_tab_name_ok "${DISK_APP_ANSWER}" "${disk_bn_old}" || return 0
  DISK_APP_B_LAYOUT="$(printf '%s\n' "${DISK_APP_B_LAYOUT}" | DISK_APP_JOIN="${DISK_APP_ANSWER}" awk -F "${DISK_TAB}" -v OFS="${DISK_TAB}" -v n="${disk_bn_line}" 'NR == n { $1 = ENVIRON["DISK_APP_JOIN"] } { print }')"
  disk_build_tab_refresh
  DISK_APP_STATUS="Renamed ${disk_bn_old} to ${DISK_APP_ANSWER}."
}

disk_build_tab_name_ok() {
  [ -n "$1" ] && [ "$1" != "$2" ] || return 1
  case "$1" in
  */*)
    DISK_APP_STATUS="A name on the disc cannot hold a slash."
    return 1
    ;;
  *) disk_build_tab_free "$1" ;;
  esac
}

disk_build_tab_edit() {
  case "$1" in
  0) DISK_APP_B_FS="$(disk_build_tab_next_fs "${DISK_APP_B_FS}")" ;;
  1) disk_build_tab_label ;;
  2) disk_build_tab_out ;;
  3) DISK_APP_B_TARGET="$(disk_build_tab_flip_target "${DISK_APP_B_TARGET}")" ;;
  *) return 0 ;;
  esac
  disk_build_tab_refresh
}

disk_build_tab_next_fs() {
  case "$1" in
  iso9660,joliet,udf) printf 'iso9660,joliet\n' ;;
  iso9660,joliet) printf 'iso9660,udf\n' ;;
  iso9660,udf) printf 'iso9660\n' ;;
  *) printf 'iso9660,joliet,udf\n' ;;
  esac
}

disk_build_tab_flip_target() {
  case "$1" in
  image) printf 'disc\n' ;;
  *) printf 'image\n' ;;
  esac
}

disk_build_tab_label() {
  disk_app_ask "Volume name, empty for the first entry's" "${DISK_APP_B_LABEL}"
  if [ "${#DISK_APP_ANSWER}" -gt 32 ]; then
    DISK_APP_STATUS="The label takes up to 32 characters."
    return 0
  fi
  DISK_APP_B_LABEL="${DISK_APP_ANSWER}"
}

disk_build_tab_out() {
  disk_app_ask "Image file to create" "path to a new .iso file"
  [ -n "${DISK_APP_ANSWER}" ] || return 0
  if [ -e "${DISK_APP_ANSWER}" ]; then
    DISK_APP_STATUS="${DISK_APP_ANSWER} already exists. Choose a new name."
    return 0
  fi
  DISK_APP_B_OUT="${DISK_APP_ANSWER}"
  DISK_APP_STATUS="Ready to build into ${DISK_APP_B_OUT}. Press b to build."
}

disk_build_tab_start() {
  disk_job_busy && return 0
  if [ -z "${DISK_APP_B_LAYOUT}" ]; then
    DISK_APP_STATUS="Add a file or folder first: press a or f."
    return 0
  fi
  DISK_BUILD_LAYOUT="${DISK_APP_B_LAYOUT}"
  DISK_BUILD_FS="${DISK_APP_B_FS}"
  DISK_BUILD_LABEL="${DISK_APP_B_LABEL}"
  case "${DISK_APP_B_TARGET}" in
  disc) disk_build_tab_to_disc ;;
  *) disk_build_tab_to_image ;;
  esac
}

disk_build_tab_to_image() {
  if [ -z "${DISK_APP_B_OUT}" ]; then
    DISK_APP_STATUS="Choose an image file first: Enter on Image."
    return 0
  fi
  DISK_BUILD_OUT="${DISK_APP_B_OUT}"
  disk_job_launch disk_build_run build "the layout into ${DISK_APP_B_OUT}"
}

disk_build_tab_to_disc() {
  if [ -n "${DISK_APP_DRIVE_NOTE}" ]; then
    DISK_APP_STATUS="There is no drive to write to."
    return 0
  fi
  disk_job_typed || return 0
  DISK_WRITE_SPEED=""
  DISK_WRITE_VERIFY=y
  DISK_WRITE_EJECT=y
  disk_job_launch disk_build_tab_disc_steps build "the layout to ${DISK_DRIVE}"
}

disk_build_tab_disc_steps() {
  DISK_BUILD_OUT="${DISK_APP_JOB_DIR}/disc.iso"
  disk_build_run || return 1
  DISK_WRITE_IMAGE="${DISK_BUILD_OUT}"
  disk_write_check || return 1
  disk_write_go
}
