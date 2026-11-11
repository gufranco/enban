#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-stab.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_TEST_GUM APP_PATH ENBAN_QUEUE_WAIT
  export ENBAN_CONFIG="${WORK}/config"
  export ENBAN_TEST_GUM_ANSWERS="${WORK}/answers"
  disk_test_shim stty "case \"\$1\" in size) printf '50 200\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
}

teardown() {
  rm -rf "${WORK}"
}

answers() {
  printf '%s\n' "$@" >"${ENBAN_TEST_GUM_ANSWERS}"
}

saved() {
  grep -x "$1" "${ENBAN_CONFIG}/settings"
}

down() {
  local count=0
  while [[ "${count}" -lt "$1" ]]; do
    printf '\\033[B'
    count=$((count + 1))
  done
}

@test "the Settings tab lists the defaults and where they are saved" {
  # Arrange
  local keys='9q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Write"*"> Verify     [x] on"*"Eject      [x] on"*"Speed      chosen by the drive"* ]]
  [[ "${shown}" == *"Read"*"Verify     [x] on"*"Build"*"Type       ISO9660, Joliet, UDF"*"Queue"*"Wait       600 seconds"*"Look"*"Theme      kodougu"* ]]
  [[ "${shown}" == *"Saved to"*"${ENBAN_CONFIG}/settings"* ]]
}

@test "space turns a switch off, saves it and changes the Write tab's default" {
  # Arrange
  local keys='9 1q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  saved "write_verify=no"
  [[ "${shown}" == *"Verify     [ ] off"* ]]
}

@test "Enter turns the eject and the read verify off" {
  # Arrange
  local keys
  local moves1 moves2
  moves1="$(down 1)"
  moves2="$(down 2)"
  keys="9${moves1}\\n${moves2}\\nq"

  # Act
  run on_terminal "${keys}"

  # Assert
  saved "write_eject=no"
  saved "read_verify=no"
}

@test "Enter on Speed sets the default write speed and refuses words" {
  # Arrange
  local keys
  local moves1
  moves1="$(down 2)"
  keys="9${moves1}\\n\\nq"
  answers 8 fast

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  saved "write_speed=8"
  [[ "${shown}" == *"The speed must be a whole number, such as 8."* ]]
}

@test "an empty speed goes back to the drive's choice" {
  # Arrange
  local keys
  local moves1
  moves1="$(down 2)"
  keys="9${moves1}\\n\\nq"
  answers 8 ""

  # Act
  run on_terminal "${keys}"

  # Assert
  saved "write_speed=auto"
}

@test "Enter on Type steps through the file systems build writes" {
  # Arrange
  local keys
  local moves1
  moves1="$(down 4)"
  keys="9${moves1}\\nq"

  # Act
  run on_terminal "${keys}"

  # Assert
  saved "build_fs=iso9660,joliet"
}

@test "Enter on Wait sets the queue wait and refuses words" {
  # Arrange
  local keys
  local moves1
  moves1="$(down 5)"
  keys="9${moves1}\\n\\nq"
  answers 30 soon

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  saved "queue_wait=30"
  [[ "${shown}" == *"The wait must be a whole number of seconds."* ]]
}

@test "Enter on Theme picks a theme and refuses one that does not exist" {
  # Arrange
  local keys
  local moves1
  moves1="$(down 6)"
  keys="9${moves1}\\n\\nq"
  answers nord sepia

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  saved "theme=nord"
  [[ "${shown}" == *"There is no theme named sepia."* ]]
}

@test "a theme from the environment is shown and kept" {
  # Arrange
  local keys
  local moves1
  moves1="$(down 6)"
  keys="9${moves1}\\nq"

  # Act
  ENBAN_THEME=dracula run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Theme      dracula, from ENBAN_THEME"* ]]
  [[ "${shown}" == *"ENBAN_THEME sets the theme. Unset it to choose one here."* ]]
}

@test "the Settings tab starts from the settings file" {
  # Arrange
  mkdir -p "${ENBAN_CONFIG}"
  printf '%s\n' write_verify=no write_speed=4 queue_wait=90 >"${ENBAN_CONFIG}/settings"

  # Act
  run on_terminal '9q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Verify     [ ] off"*"Speed      4x"*"Wait       90 seconds"* ]]
}

@test "the Settings tab says when the settings cannot be saved" {
  # Arrange
  printf 'not a folder\n' >"${WORK}/blocked"
  export ENBAN_CONFIG="${WORK}/blocked/enban"

  # Act
  run on_terminal '9 q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Unable to save the settings to ${ENBAN_CONFIG}/settings."* ]]
}

@test "the Settings tab ignores other keys" {
  # Arrange
  local keys='9zq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Settings"*"> Verify"* ]]
}
