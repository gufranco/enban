#!/usr/bin/env bats
# shellcheck disable=SC2016

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-app.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME NO_COLOR
}

teardown() {
  rm -rf "${WORK}"
}

start_app() {
  local -a shell_words
  local search_path command_line
  read -r -a shell_words <<<"${ENBAN_TEST_SHELL:-sh}"
  search_path="$(disk_test_path)"
  case "${ENBAN_TEST_OS}" in
  Darwin) PATH="${search_path}" script -q /dev/null "${shell_words[@]}" "${REPO_DIR}/bin/enban" "$@" ;;
  *)
    command_line="$(printf '%q ' "${shell_words[@]}" "${REPO_DIR}/bin/enban" "$@")"
    PATH="${search_path}" script -qec "${command_line}" /dev/null
    ;;
  esac
}

send_when_drawn() {
  disk_test_wait_for "${WORK}/out" 'What would you like to do' 100 || return 0
  printf '%b' "$1"
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

screen() {
  LC_ALL=C sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "${WORK}/out"
}

@test "enban opens in the alternate screen and gives it back on q" {
  # Arrange
  local keys="q"

  # Act
  run on_terminal "${keys}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *$'\033[?1049h'* ]]
  [[ "${output}" == *$'\033[?1049l'* ]]
  [[ "${output}" == *$'\033[?25h'* ]]
}

@test "enban draws the home tab with its jobs" {
  # Arrange
  local keys="q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(screen)"
  [[ "${shown}" == *"What would you like to do?"* ]]
  [[ "${shown}" == *"Write image to disc"* ]]
}

@test "a digit switches to that tab" {
  # Arrange
  local keys="1q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(screen)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"q           quit and restore the terminal"* ]]
}

@test "the right and left arrows move between tabs" {
  # Arrange
  local keys='\033[C\033[D\033[Cq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(screen)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"left/right  previous or next tab"* ]]
}

@test "a digit past the last tab, up, down, escape and other keys change nothing" {
  # Arrange
  local keys='7\033[A\033[B\033[Zxq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(screen)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" != *"left/right  previous or next tab"* ]]
}

@test "enter changes nothing and Ctrl+D closes the app" {
  # Arrange
  local keys='\n\004'

  # Act
  run on_terminal "${keys}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *$'\033[?1049l'* ]]
}

@test "the end of input reads as the end of the session" {
  # Arrange
  local call='disk_app_key; printf "%s\n" "${DISK_APP_KEY}"'

  # Act
  run disk_test_call eval "${call}" </dev/null

  # Assert
  [[ "${output}" == "eof" ]]
}

@test "the mono theme draws the current tab in brackets" {
  # Arrange
  local keys="q"

  # Act
  run on_terminal "${keys}" --theme mono

  # Assert
  local shown
  shown="$(screen)"
  [[ "${shown}" == *"[0 Home]"* ]]
}

@test "enban never opens the app without a terminal" {
  # Arrange
  local input=/dev/null

  # Act
  run disk_test_run enban <"${input}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the app needs a terminal. run 'enban help' for usage." ]]
}

@test "a terminal that reports no size gets 80 columns" {
  # Arrange
  local call='disk_app_size; printf "%s %s\n" "${DISK_APP_ROWS}" "${DISK_APP_COLS}"'

  # Act
  run disk_test_call eval "${call}" </dev/null

  # Assert
  [[ "${output}" == "24 80" ]]
}

@test "a narrow terminal is drawn at 60 columns" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '10 40\\n' ;; esac"
  local call='disk_app_size; printf "%s\n" "${DISK_APP_COLS}"'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "60" ]]
}

@test "leaving warns when the terminal still hides typing" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in -a) printf 'speed 9600 baud; -echo icanon\\n' ;; esac"
  local call='DISK_APP_STTY=changed disk_app_leave'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: warning: the terminal still hides what you type. run stty sane to restore it."* ]]
}

@test "leaving draws the hidden-typing warning with gum" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in -a) printf 'speed 9600 baud; -echo icanon\\n' ;; esac"
  local call='disk_ui_setup && DISK_APP_STTY=changed disk_app_leave'

  # Act
  ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log" run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"WARN enban: the terminal still hides what you type. run stty sane to restore it."* ]]
}

@test "leaving twice restores the terminal only once" {
  # Arrange
  disk_test_shim stty "printf 'called %s\\n' \"\$*\" >>'${WORK}/stty.log'"
  local call='disk_app_leave'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ ! -e "${WORK}/stty.log" ]]
}

@test "a colour turns into its red, green and blue parts" {
  # Arrange
  local colour="#F25D94"

  # Act
  run disk_test_call disk_app_rgb "${colour}"

  # Assert
  [[ "${output}" == "242;93;148" ]]
}
