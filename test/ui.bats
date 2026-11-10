#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-ui.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME NO_COLOR
  export ENBAN_TEST_GUM=1
  export ENBAN_TEST_GUM_LOG="${WORK}/gum.log"
  export ENBAN_TEST_GUM_ANSWERS="${WORK}/answers"
  : >"${ENBAN_TEST_GUM_LOG}"
}

teardown() {
  rm -rf "${WORK}"
}

called() {
  grep -q -F -- "$1" "${ENBAN_TEST_GUM_LOG}"
}

@test "doctor draws its rows in a table" {
  # Arrange
  local expected="dd"

  # Act
  run disk_test_run enban doctor </dev/null

  # Assert
  [[ "${output}" == *"Tool"*"State"*"Detail"* ]]
  [[ "${output}" == *"${expected}"* ]]
}

@test "doctor reports a missing tool below the table" {
  # Arrange
  local farm
  farm="$(disk_test_farm od)"

  # Act
  run disk_test_run_path "${farm}" enban doctor </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"ERROR enban: a required tool is missing."* ]]
}

@test "version shows the version and platform as badges" {
  # Arrange
  local version
  version="$(sed -n 's/^ENBAN_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

  # Act
  run disk_test_run enban version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "enban ${version} platform "* ]]
}

@test "help is formatted with gum" {
  # Arrange
  local expected="## Usage"

  # Act
  run disk_test_run enban help </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${expected}"* ]]
  called "format --theme pink"
}

@test "--theme picks the palette over the environment" {
  # Arrange
  local theme="nord"

  # Act
  KODOUGU_THEME=dracula ENBAN_THEME=gruvbox run disk_test_run enban --theme "${theme}" version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #88C0D0"
}

@test "the mono theme draws doctor without colour" {
  # Arrange
  local theme=mono

  # Act
  run disk_test_run enban --theme "${theme}" doctor </dev/null

  # Assert
  [[ "${output}" == *"Ready. Every tool enban needs is here."* ]]
  called "style --bold -- Ready. Every tool enban needs is here."
}

@test "doctor draws a missing cdrdao as a warning on Linux" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
  local farm
  farm="$(disk_test_farm cdrdao)"

  # Act
  run disk_test_run_path "${farm}" enban doctor </dev/null

  # Assert
  [[ "${output}" == *"cdrdao"*"warn"*"cdrdao package"* ]]
}

@test "an unknown command is drawn as an error" {
  # Arrange
  local command=burn

  # Act
  run disk_test_run enban "${command}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"ERROR enban: unknown command 'burn'"* ]]
}
