#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_project_lines() {
  printf '%s\n' "${DISK_PROJECT_MAGIC}"
  printf 'fs=%s\nlabel=%s\npublisher=%s\n' "${DISK_BUILD_FS}" "${DISK_BUILD_LABEL}" "${DISK_BUILD_PUBLISHER}"
  printf 'date=%s\nboot=%s\nemulation=%s\n' "${DISK_BUILD_DATE}" "${DISK_BUILD_BOOT}" "${DISK_BUILD_EMULATION}"
  disk_pl_dvd="$(disk_settings_word "${DISK_BUILD_DVD}")"
  disk_pl_bdmv="$(disk_settings_word "${DISK_BUILD_BDMV}")"
  printf 'platform=%s\ndvd_video=%s\nbdmv=%s\n' "${DISK_BUILD_PLATFORM}" "${disk_pl_dvd}" "${disk_pl_bdmv}"
  printf 'udf_version=%s\n' "${DISK_BUILD_UDF_VERSION}"
  disk_pl_here="$(pwd)"
  printf '%s\n' "${DISK_BUILD_LAYOUT}" | awk -F "${DISK_TAB}" -v here="${disk_pl_here}" '
    NF { path = $2; if (substr(path, 1, 1) != "/") path = here "/" path; print "entry=" $1 FS path }'
}

disk_project_save() {
  disk_ps_text="$(disk_project_lines)"
  disk_ps_dir="$(dirname "$1")"
  disk_ps_part="$(mktemp "${disk_ps_dir}/.enban-project.XXXXXX")" || return 1
  printf '%s\n' "${disk_ps_text}" >"${disk_ps_part}" && disk_layer_keep "$1" && mv -f "${disk_ps_part}" "$1" && return 0
  rm -f "${disk_ps_part}"
  return 1
}

disk_build_project() {
  if [ -n "${DISK_BUILD_OPTION}" ]; then
    disk_cli_hint "option '${DISK_BUILD_OPTION}' cannot go with --project, which holds the build options"
    return 1
  fi
  if [ -z "${DISK_OPERAND}" ] || [ -n "${DISK_OPERAND_TWO}" ]; then
    disk_cli_hint "build --project takes only the image file to create"
    return 1
  fi
  if ! disk_project_read "${DISK_BUILD_PROJECT}"; then
    disk_error "${DISK_PROJECT_PROBLEM}"
    return 1
  fi
  DISK_BUILD_OUT="${DISK_OPERAND}"
  disk_build_run
}

disk_project_read() {
  DISK_PROJECT_PROBLEM=""
  if [ ! -f "$1" ]; then
    DISK_PROJECT_PROBLEM="there is no project at $1."
    return 1
  fi
  disk_pr_first="$(sed -n '1p' "$1")"
  if [ "${disk_pr_first}" != "${DISK_PROJECT_MAGIC}" ]; then
    DISK_PROJECT_PROBLEM="$1 is not an enban project."
    return 1
  fi
  disk_pr_body="$(sed '1d' "$1")"
  DISK_BUILD_LAYOUT=""
  disk_pr_line=1
  while IFS= read -r disk_pr_text; do
    disk_pr_line=$((disk_pr_line + 1))
    disk_project_field "$1" "${disk_pr_line}" "${disk_pr_text%%=*}" "${disk_pr_text#*=}" || return 1
  done <<EOF
${disk_pr_body}
EOF
  [ -n "${DISK_BUILD_LAYOUT}" ] && return 0
  DISK_PROJECT_PROBLEM="$1 has no files or folders to build."
  return 1
}

disk_project_field() {
  case "$3" in
  '') return 0 ;;
  fs) DISK_BUILD_FS="$4" ;;
  label) DISK_BUILD_LABEL="$4" ;;
  publisher) DISK_BUILD_PUBLISHER="$4" ;;
  date) DISK_BUILD_DATE="$4" ;;
  boot) DISK_BUILD_BOOT="$4" ;;
  emulation) DISK_BUILD_EMULATION="$4" ;;
  platform) DISK_BUILD_PLATFORM="$4" ;;
  udf_version) DISK_BUILD_UDF_VERSION="$4" ;;
  dvd_video | bdmv) disk_project_switch "$@" ;;
  entry) disk_project_entry "$@" ;;
  *)
    DISK_PROJECT_PROBLEM="$1 line $2: unknown setting $3."
    return 1
    ;;
  esac
}

disk_project_switch() {
  case "$4" in
  yes) disk_pw_value=y ;;
  no) disk_pw_value=n ;;
  *)
    DISK_PROJECT_PROBLEM="$1 line $2: $3 must be yes or no, got: $4"
    return 1
    ;;
  esac
  case "$3" in
  dvd_video) DISK_BUILD_DVD="${disk_pw_value}" ;;
  *) DISK_BUILD_BDMV="${disk_pw_value}" ;;
  esac
}

disk_project_entry() {
  case "$4" in
  *"${DISK_TAB}"/*) : ;;
  *)
    DISK_PROJECT_PROBLEM="$1 line $2: an entry is a name, a tab and a full path."
    return 1
    ;;
  esac
  DISK_BUILD_LAYOUT="$(printf '%s\n%s\n' "${DISK_BUILD_LAYOUT}" "$4" | sed '/^$/d')"
}
