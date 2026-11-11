#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-dtab.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_TEST_GUM APP_PATH
  export ENBAN_DATA="${WORK}/data"
  DISC="${WORK}/disc.iso"
  : >"${DISC}"
  export ENBAN_TEST_GUM_ANSWERS="${WORK}/answers"
  disk_test_shim stty "case \"\$1\" in size) printf '50 200\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
}

teardown() {
  rm -rf "${WORK}"
}

answers() {
  printf '%s\n' "$@" >"${ENBAN_TEST_GUM_ANSWERS}"
}

past_runs() {
  mkdir -p "${ENBAN_DATA}/discovery"
  printf 'sector,sectors,seconds,kib_per_second\n0,10,0.5,40\n10,10,0.25,80\n20,10,1,20\n' >"${ENBAN_DATA}/discovery/first.csv"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    2026-11-01T10:00:00Z /dev/sr0 DVD-R 30 8 good "${ENBAN_DATA}/discovery/first.csv" \
    2026-11-02T10:00:00Z /dev/sr0 CD-R 30 auto poor "${ENBAN_DATA}/discovery/gone.csv" \
    >"${ENBAN_DATA}/discovery/runs.tsv"
}

@test "the Discovery tab shows its fields and says when there are no runs" {
  # Arrange
  local keys='5q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Sectors    all free"*"Speed      chosen by the drive"* ]]
  [[ "${shown}" == *"No runs yet."* ]]
}

@test "Enter on Sectors sets how many sectors the test writes" {
  # Arrange
  answers 500

  # Act
  run on_terminal '5\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Sectors    500"* ]]
}

@test "Enter on Sectors refuses a count that is not a number" {
  # Arrange
  answers many

  # Act
  run on_terminal '5\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"The sectors must be a whole number from 1, or empty for all free."* ]]
  [[ "${shown}" == *"> Sectors    all free"* ]]
}

@test "Enter on Speed sets the write speed and refuses words" {
  # Arrange
  answers 8 fast

  # Act
  run on_terminal '5\033[B\n\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Speed      8x"* ]]
  [[ "${shown}" == *"The speed must be a whole number, such as 8."* ]]
}

@test "the last run draws its read rate and the runs compare below" {
  # Arrange
  past_runs

  # Act
  run on_terminal '5q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Last run, CD-R on /dev/sr0 at auto: poor"* ]]
  [[ "${shown}" == *"The read rate of this run was not saved."* ]]
  [[ "${shown}" == *"2026-11-02"*"CD-R"*"auto"*"30"*"poor"* ]]
  [[ "${shown}" == *"2026-11-01"*"DVD-R"*"8x"*"30"*"good"* ]]
}

@test "the last run draws a bar for each stretch of the disc" {
  # Arrange
  past_runs
  awk -F '\t' -v OFS='\t' 'NR == 2 { $7 = ENVIRON["ENBAN_DATA"] "/discovery/first.csv" } { print }' "${ENBAN_DATA}/discovery/runs.tsv" >"${WORK}/runs"
  mv "${WORK}/runs" "${ENBAN_DATA}/discovery/runs.tsv"

  # Act
  run on_terminal '5q'

  # Assert
  local shown bars
  shown="$(last_frame)"
  bars="$(printf '\342\226\204\342\226\210\342\226\202')"
  [[ "${shown}" == *"Read rate  ${bars}  20 to 80 KiB/s"* ]]
}

@test "t needs a drive" {
  # Arrange
  local keys='5tq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to test."* ]]
}

@test "t writes nothing without the drive's name" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 64 22160
  answers wrong

  # Act
  run on_terminal '5tq' --drive "stdio:${DISC}"

  # Assert
  local shown size
  shown="$(last_frame)"
  size="$(wc -c <"${DISC}")"
  [[ "${shown}" == *"Nothing was written."* ]]
  [[ "${size//[[:space:]]/}" -eq 0 ]]
}

@test "t tests the disc and shows the verdict" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 64 22160
  answers disc.iso

  # Act
  run on_terminal_in_steps '5t' 'passed discovery' '\nq' --drive "stdio:${DISC}"

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"Result"*"Read back    64 of 64 sectors"*"Done. stdio:${DISC} passed discovery."* ]]
  [[ "${final}" == *"Last run, DVD-R on stdio:${DISC} at auto: good"* ]]
}

@test "c cancels a discovery test" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 64 22160
  disk_test_drive_flag slow
  answers disc.iso

  # Act
  run on_terminal_in_steps '5t' 'Press c to cancel' 'cq' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Cancelled while testing. The disc holds part of the test data."* ]]
}

@test "the Discovery tab starts nothing while a read runs" {
  # Arrange
  local call='DISK_APP_JOB=running DISK_APP_JOB_KIND=read DISK_APP_JOB_PID=1; disk_discovery_tab_start; printf "%s|%s|%s\n" "${DISK_APP_JOB_KIND}" "${DISK_APP_JOB_PID}" "${DISK_APP_STATUS}"'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "read|1|A read is running. Press c on its tab to cancel it first." ]]
}

@test "the Discovery tab ignores other keys" {
  # Arrange
  local keys='5zq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Discovery"*"> Sectors"* ]]
}
