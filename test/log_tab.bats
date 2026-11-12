#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-ltab.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_TEST_GUM APP_PATH
  export ENBAN_DATA="${WORK}/data"
  SRC="${WORK}/photos"
  OUT="${WORK}/out.iso"
  mkdir -p "${SRC}"
  head -c 3000 /dev/urandom >"${SRC}/a.txt"
  export ENBAN_TEST_GUM_ANSWERS="${WORK}/answers"
  disk_test_shim stty "case \"\$1\" in size) printf '50 200\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
}

teardown() {
  rm -rf "${WORK}"
}

answers() {
  printf '%s\n' "$@" >"${ENBAN_TEST_GUM_ANSWERS}"
}

build_keys() {
  printf '%s' '3f\033[B\033[B\033[B\nb'
}

@test "the log starts with what enban found in the drive" {
  # Arrange
  local keys='8q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" =~ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\ WARN\ +No\ drive\ chosen\. ]]
}

@test "the log counts its lines per level" {
  # Arrange
  local keys='8q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"INFO 0   WARN 1   ERROR 0"* ]]
}

@test "the log draws each level in its theme colour" {
  # Arrange
  local keys='8q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local raw
  raw="$(<"${WORK}/out")"
  [[ "${raw}" == *$'\033[38;2;255;184;108mWARN\033[0m'* ]]
}

@test "the log stays plain in the mono theme" {
  # Arrange
  local keys='8q'
  export ENBAN_THEME=mono

  # Act
  run on_terminal "${keys}"

  # Assert
  local raw
  raw="$(<"${WORK}/out")"
  [[ "${raw}" != *"mWARN"* ]]
}

@test "the log names the drive and the disc it found" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  : >"${WORK}/disc.iso"

  # Act
  run on_terminal '8q' --drive "stdio:${WORK}/disc.iso"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"INFO  Found stdio:${WORK}/disc.iso, YOYODYNE WARP DRIVE FX01, DVD-R"* ]]
}

@test "the log says when the drive cannot be read" {
  # Arrange
  local drive="stdio:${WORK}/missing/disc.iso"
  local wanted="ERROR Unable to read the drive ${drive}."

  # Act
  run on_terminal '8q' --drive "${drive}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"${wanted}"* ]]
}

@test "the log records a job that starts and finishes" {
  # Arrange
  local keys
  keys="$(build_keys)"
  answers "${SRC}" "${OUT}"

  # Act
  run on_terminal_in_steps "${keys}" 'is built from' '8q'

  # Assert
  local kept
  kept="$(cat "${ENBAN_DATA}"/logs/*.log)"
  [[ "${kept}" == *"INFO  Started build: the layout into ${OUT}"* ]]
  [[ "${kept}" == *"INFO  Finished build: Done. ${OUT} is built from 1 entry."* ]]
}

@test "the log records why a job failed" {
  # Arrange
  disk_test_shim mkisofs "exit 1"
  disk_test_shim genisoimage "exit 1"
  local keys
  keys="$(build_keys)"
  answers "${SRC}" "${OUT}"

  # Act
  run on_terminal_in_steps "${keys}" 'the result says why' '8q'

  # Assert
  local kept
  kept="$(cat "${ENBAN_DATA}"/logs/*.log)"
  [[ "${kept}" == *"ERROR The build failed: unable to build ${OUT} from the layout."* ]]
}

@test "the log records a cancelled job" {
  # Arrange
  disk_test_shim mkisofs "sleep 45"
  disk_test_shim genisoimage "sleep 45"
  local keys
  keys="$(build_keys)"
  answers "${SRC}" "${OUT}" y

  # Act
  run on_terminal_in_steps "${keys}" 'Press c to cancel' 'c8q'

  # Assert
  local kept
  kept="$(cat "${ENBAN_DATA}"/logs/*.log)"
  [[ "${kept}" == *"WARN  Cancelled build: the layout into ${OUT}"* ]]
}

@test "f shows warnings and errors, then errors, then everything" {
  # Arrange
  local keys
  keys="$(build_keys)"
  answers "${SRC}" "${OUT}"

  # Act
  run on_terminal_in_steps "${keys}" 'is built from' '8fq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"showing warnings and errors"* ]]
  [[ "${shown}" != *"Started build"* ]]
}

@test "f steps from errors back to everything" {
  # Arrange
  local keys='8fff'

  # Act
  run on_terminal_in_steps "${keys}" 'showing everything' 'q'

  # Assert
  local shown
  shown="$(screen)"
  [[ "${shown}" == *"showing errors"*"Nothing matches."* ]]
  [[ "${shown}" == *"showing everything"*"No drive chosen."* ]]
}

@test "/ keeps only the lines that hold the search" {
  # Arrange
  local keys
  keys="$(build_keys)"
  answers "${SRC}" "${OUT}" "Finished"

  # Act
  run on_terminal_in_steps "${keys}" 'is built from' '8/q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"matching Finished"* ]]
  [[ "${shown}" == *"Finished build"* ]]
  [[ "${shown}" != *"Started build"* ]]
}

@test "an empty search shows every line again" {
  # Arrange
  answers zzz ""

  # Act
  run on_terminal_in_steps '8/' 'Nothing matches' '/q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"No drive chosen."* ]]
  [[ "${shown}" != *"matching"* ]]
}

@test "s saves the log and never overwrites a file" {
  # Arrange
  printf 'keep\n' >"${WORK}/taken.log"
  answers "${WORK}/taken.log" "${WORK}/saved.log"

  # Act
  run on_terminal_in_steps '8s' 'already exists' 'sq'

  # Assert
  local shown saved kept
  shown="$(screen)"
  saved="$(cat "${WORK}/saved.log")"
  kept="$(cat "${WORK}/taken.log")"
  [[ "${shown}" == *"${WORK}/taken.log already exists. Choose a new name."* ]]
  [[ "${shown}" == *"Saved the log to ${WORK}/saved.log."* ]]
  [[ "${saved}" == *"No drive chosen."* ]]
  [[ "${kept}" == "keep" ]]
}

@test "the session log is kept under the data folder when enban quits" {
  # Arrange
  local keys='q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local kept
  kept="$(cat "${ENBAN_DATA}"/logs/*.log)"
  [[ "${kept}" == *"WARN  No drive chosen."* ]]
}

@test "enban warns when it cannot keep the session log" {
  # Arrange
  printf 'not a folder\n' >"${WORK}/blocked"
  export ENBAN_DATA="${WORK}/blocked/data"

  # Act
  run on_terminal 'q'

  # Assert
  [[ "${output}" == *"enban: "*"unable to keep the log in"* ]]
  [[ ! -e "${ENBAN_DATA}" ]]
}
