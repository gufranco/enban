#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_file_text() {
  dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | tr -d '\000'
}

disk_iso_is() {
  disk_ii_magic="$(disk_file_text "$1" 32769 5)"
  [ "${disk_ii_magic}" = CD001 ]
}

disk_label_check() {
  if [ ! -f "${DISK_LABEL_IMAGE}" ]; then
    disk_error "no image at ${DISK_LABEL_IMAGE}."
    return 1
  fi
  if ! disk_iso_is "${DISK_LABEL_IMAGE}"; then
    disk_error "stopped: ${DISK_LABEL_IMAGE} is not an ISO image, so it has no volume label to change."
    return 1
  fi
  case "${DISK_LABEL_NAME}" in
  '' | *[!\ -~]* | *[*/:\;?\\]*)
    disk_error "the label takes plain ASCII characters other than * / : ; ? and \\, got: ${DISK_LABEL_NAME}"
    return 1
    ;;
  *) : ;;
  esac
  [ "${#DISK_LABEL_NAME}" -le 32 ] && return 0
  disk_error "the label takes up to 32 characters, got ${#DISK_LABEL_NAME}."
  return 1
}

disk_label_byte() {
  od -An -tu1 -j "$2" -N 1 "$1" | tr -d '[:space:]'
}

disk_label_patch() {
  dd of="${DISK_LABEL_IMAGE}" bs=1 seek="$1" count=32 conv=notrunc 2>/dev/null
}

disk_label_primary() {
  disk_lp_upper="$(printf '%s' "${DISK_LABEL_NAME}" | tr '[:lower:]' '[:upper:]')"
  disk_lp_name="$(printf '%s' "${disk_lp_upper}" | tr -c 'A-Z0-9_' '_')"
  printf '%-32s' "${disk_lp_name}"
}

disk_label_joliet() {
  disk_lj_rest="$(printf '%.16s' "${DISK_LABEL_NAME}")"
  disk_lj_count=0
  while [ -n "${disk_lj_rest}" ]; do
    printf '\000%s' "${disk_lj_rest%"${disk_lj_rest#?}"}"
    disk_lj_rest="${disk_lj_rest#?}"
    disk_lj_count=$((disk_lj_count + 1))
  done
  while [ "${disk_lj_count}" -lt 16 ]; do
    printf '\000 '
    disk_lj_count=$((disk_lj_count + 1))
  done
}

disk_label_walk() {
  disk_lw_sector=16
  DISK_LABEL_JOLIET=n
  while [ "${disk_lw_sector}" -lt 48 ]; do
    disk_lw_at=$((disk_lw_sector * 2048))
    disk_lw_type="$(disk_label_byte "${DISK_LABEL_IMAGE}" "${disk_lw_at}")"
    case "${disk_lw_type}" in
    255) return 0 ;;
    1) disk_label_primary | disk_label_patch $((disk_lw_at + 40)) ;;
    2) disk_label_supplementary "${disk_lw_at}" ;;
    *) : ;;
    esac
    disk_lw_sector=$((disk_lw_sector + 1))
  done
}

disk_label_supplementary() {
  disk_ys_escape="$(disk_file_text "${DISK_LABEL_IMAGE}" $(($1 + 88)) 2)"
  [ "${disk_ys_escape}" = "%/" ] || return 0
  disk_label_joliet | disk_label_patch $(($1 + 40))
  DISK_LABEL_JOLIET=y
}

disk_label_udf() {
  disk_lu_sector=16
  while [ "${disk_lu_sector}" -lt 64 ]; do
    disk_lu_id="$(disk_file_text "${DISK_LABEL_IMAGE}" $((disk_lu_sector * 2048 + 1)) 4)"
    case "${disk_lu_id}" in
    NSR0) return 0 ;;
    *) disk_lu_sector=$((disk_lu_sector + 1)) ;;
    esac
  done
  return 1
}

disk_label_backup() {
  DISK_LABEL_BACKUP="${DISK_LABEL_IMAGE}.bak"
  disk_lb_count=1
  while [ -e "${DISK_LABEL_BACKUP}" ]; do
    if [ "${disk_lb_count}" -ge 100 ]; then
      disk_error "stopped: ${DISK_LABEL_IMAGE}.bak to .bak.99 all exist, so there is no room for a backup. nothing was changed."
      return 1
    fi
    DISK_LABEL_BACKUP="${DISK_LABEL_IMAGE}.bak.${disk_lb_count}"
    disk_lb_count=$((disk_lb_count + 1))
  done
  cp -c "${DISK_LABEL_IMAGE}" "${DISK_LABEL_BACKUP}" 2>/dev/null && return 0
  cp "${DISK_LABEL_IMAGE}" "${DISK_LABEL_BACKUP}" 2>/dev/null && return 0
  rm -f "${DISK_LABEL_BACKUP}"
  disk_error "unable to back up ${DISK_LABEL_IMAGE} to ${DISK_LABEL_BACKUP}, so nothing was changed."
  return 1
}

disk_label_run() {
  disk_label_check || return 1
  disk_label_backup || return 1
  disk_label_walk
  disk_yr_primary="$(disk_label_primary | sed 's/ *$//')"
  disk_yr_line="Done. ${DISK_LABEL_IMAGE} is labelled ${disk_yr_primary}"
  disk_yr_joliet="$(printf '%.16s' "${DISK_LABEL_NAME}")"
  [ "${DISK_LABEL_JOLIET}" = n ] || disk_yr_line="${disk_yr_line}, ${disk_yr_joliet} on Joliet"
  disk_label_udf_too || return 1
  [ "${DISK_LABEL_UDF}" = n ] || disk_yr_line="${disk_yr_line}, ${DISK_LABEL_NAME} on UDF"
  disk_raw_done "${disk_yr_line}. The original is kept as ${DISK_LABEL_BACKUP}."
}

disk_label_udf_too() {
  DISK_LABEL_UDF=n
  disk_label_udf || return 0
  disk_lt_status=0
  disk_udf_label || disk_lt_status="$?"
  case "${disk_lt_status}" in
  0) DISK_LABEL_UDF=y ;;
  1) disk_warning "${DISK_LABEL_IMAGE} has UDF with no anchor at sector 256, so its UDF label is unchanged." ;;
  *)
    mv -f "${DISK_LABEL_BACKUP}" "${DISK_LABEL_IMAGE}"
    disk_error "the UDF checksums of ${DISK_LABEL_IMAGE} could not be computed, so the image is restored as it was."
    return 1
    ;;
  esac
}
