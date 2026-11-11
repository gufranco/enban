#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_udf_rev() {
  case "$1" in
  1.50) printf '336\n' ;;
  2.00) printf '512\n' ;;
  2.01) printf '513\n' ;;
  2.60) printf '608\n' ;;
  *) printf '592\n' ;;
  esac
}

disk_udf_row() {
  case "$1" in
  *"${DISK_TAB}"*)
    disk_error "a UDF image cannot take the name ${1}, which holds a tab."
    return 1
    ;;
  *) : ;;
  esac
  if [ -d "$2" ]; then
    printf 'd\t%s\t0\t%s\n' "$1" "$2"
    return 0
  fi
  if [ -f "$2" ]; then
    disk_ur_bytes="$(disk_file_bytes "$2")" || return 1
    printf 'f\t%s\t%s\t%s\n' "$1" "${disk_ur_bytes}" "$2"
    return 0
  fi
  disk_error "a UDF image takes folders and files, and ${2} is neither."
  return 1
}

disk_udf_rows() {
  while IFS= read -r disk_uq_rel; do
    disk_udf_row "$1${disk_uq_rel#./}" "$2/${disk_uq_rel#./}" || return 1
  done
}

disk_udf_walk() {
  disk_uk_newline="$(cd "$1" && find . -name "*${DISK_NEWLINE}*" | sed -n '1p')"
  if [ -n "${disk_uk_newline}" ]; then
    disk_error "a UDF image cannot take a name that holds a line break, and ${1} has one."
    return 1
  fi
  (cd "$1" && find . -mindepth 1) | disk_udf_rows "$2" "${1%/}"
}

disk_udf_entries() {
  while IFS="${DISK_TAB}" read -r disk_ue_name disk_ue_source; do
    disk_udf_row "${disk_ue_name}" "${disk_ue_source}" || return 1
    [ -d "${disk_ue_source}" ] || continue
    disk_udf_walk "${disk_ue_source}" "${disk_ue_name}/" || return 1
  done
}

disk_udf_tree() {
  if [ -z "${DISK_BUILD_LAYOUT}" ]; then
    disk_udf_walk "${DISK_BUILD_SOURCE}" ""
    return
  fi
  printf '%s\n' "${DISK_BUILD_LAYOUT}" | cut -f 1,2 | disk_udf_entries
}

disk_udf_copy() {
  if [ "$3" = 1 ]; then
    dd if="$4" of="$1" bs=1048576 seek=$(($2 / 512)) conv=notrunc 2>/dev/null
    return
  fi
  dd if="$4" of="$1" bs=2048 seek="$2" conv=notrunc 2>/dev/null
}

disk_udf_apply() {
  while IFS="${DISK_TAB}" read -r disk_uv_kind disk_uv_one disk_uv_two disk_uv_three; do
    case "${disk_uv_kind}" in
    N) dd if=/dev/zero of="$1" bs=2048 count=0 seek="${disk_uv_one}" 2>/dev/null || return 1 ;;
    W)
      printf '%b' "${disk_uv_two}" >"$1.sector" || return 1
      dd if="$1.sector" of="$1" bs=2048 seek="${disk_uv_one}" conv=notrunc 2>/dev/null || return 1
      ;;
    *) disk_udf_copy "$1" "${disk_uv_one}" "${disk_uv_two}" "${disk_uv_three}" || return 1 ;;
    esac
  done
}

disk_udf_plan() {
  disk_up_rev="$(disk_udf_rev "${DISK_BUILD_UDF_REV}")"
  disk_up_date="${DISK_BUILD_DATE}"
  [ -n "${disk_up_date}" ] || disk_up_date="$(date -u +%Y%m%d%H%M%S)"
  disk_up_status=0
  awk -v REV="${disk_up_rev}" -v LABEL="${DISK_BUILD_NAME}" -v DATE="${disk_up_date}" \
    -f "${DISK_LIB}/udf.awk" "$1.tree" >"$1.plan" || disk_up_status="$?"
  [ "${disk_up_status}" -ne 3 ] && return "${disk_up_status}"
  disk_error "a UDF image cannot take a name with a character outside Unicode's first plane, such as an emoji."
  return 1
}

disk_udf_write() {
  disk_uw_status=0
  disk_udf_tree >"$1.tree" || disk_uw_status=1
  [ "${disk_uw_status}" -ne 0 ] || disk_udf_plan "$1" || disk_uw_status=1
  [ "${disk_uw_status}" -ne 0 ] || disk_udf_apply "$1" <"$1.plan" || disk_uw_status=1
  rm -f "$1.tree" "$1.plan" "$1.sector"
  return "${disk_uw_status}"
}
