#!/usr/bin/env bash
# shellcheck disable=SC2154

APP_TIME_LIMIT=120

start_app() {
  local -a shell_words
  local search_path command_line limit_tool
  read -r -a shell_words <<<"${ENBAN_TEST_SHELL:-sh}"
  search_path="${APP_PATH:-}"
  [[ -n "${search_path}" ]] || search_path="$(disk_test_path)"
  case "${ENBAN_TEST_OS}" in
  Darwin) PATH="${search_path}" script -q /dev/null "${shell_words[@]}" "${REPO_DIR}/bin/enban" "$@" ;;
  *)
    command_line="$(printf '%q ' "${shell_words[@]}" "${REPO_DIR}/bin/enban" "$@")"
    limit_tool="$(command -v timeout)"
    PATH="${search_path}" "${limit_tool}" "${APP_TIME_LIMIT}" script -qec "${command_line}" /dev/null
    ;;
  esac
}

send_when_drawn() {
  disk_test_wait_for "${WORK}/out" 'What would you like to do' 100 || return 0
  printf '%b' "$1"
}

send_in_steps() {
  disk_test_wait_for "${WORK}/out" 'What would you like to do' 100 || return 0
  printf '%b' "$1"
  disk_test_wait_for "${STEP_FILE:-${WORK}/out}" "$2" 100 || return 0
  printf '%b' "$3"
}

on_terminal() {
  local keys="$1"
  local status=0
  shift
  : >"${WORK}/out"
  set -o pipefail
  send_when_drawn "${keys}" | start_app "$@" >"${WORK}/out" 2>&1 || status="$?"
  cat "${WORK}/out"
  return "${status}"
}

on_terminal_in_steps() {
  local first="$1"
  local wait_for="$2"
  local then="$3"
  local status=0
  shift 3
  : >"${WORK}/out"
  set -o pipefail
  send_in_steps "${first}" "${wait_for}" "${then}" | start_app "$@" >"${WORK}/out" 2>&1 || status="$?"
  cat "${WORK}/out"
  return "${status}"
}

plain() {
  LC_ALL=C sed "s/"$'\033'"\\[[0-9;?]*[A-Za-z]//g"
}

screen() {
  plain <"${WORK}/out"
}

last_frame() {
  local all
  all="$(cat "${WORK}/out")"
  printf '%s\n' "${all##*$'\033[H\033[2J'}" | plain
}
