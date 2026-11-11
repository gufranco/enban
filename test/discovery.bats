#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-disc.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  export ENBAN_DATA="${WORK}/data"
  DISC="${WORK}/disc.iso"
  DRIVE="stdio:${DISC}"
  CSV="${WORK}/run.csv"
  : >"${DISC}"
}

teardown() {
  rm -rf "${WORK}"
}

linux_only() {
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
}

blank_disc() {
  disk_test_drive 0011 "DVD-R sequential recording" "$1" 22160
}

pattern_line() {
  printf 'enban discovery %010d.....\n' "$1"
}

@test "enban discovery fills every free sector and reads each one back" {
  # Arrange
  linux_only
  blank_disc 128

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" --csv "${CSV}" <<<"disc.iso"

  # Assert
  local first last want_first want_last
  first="$(head -c 32 "${DISC}")"
  dd if="${DISC}" of="${WORK}/last.bin" bs=2048 skip=127 count=1 2>/dev/null
  last="$(head -c 32 "${WORK}/last.bin")"
  want_first="$(pattern_line 0)"
  want_last="$(pattern_line 127)"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Written      128 sectors"* ]]
  [[ "${output}" == *"Read back    128 of 128 sectors"* ]]
  [[ "${output}" == *"Done. ${DRIVE} passed discovery." ]]
  [[ "${first}" == "${want_first}" ]]
  [[ "${last}" == "${want_last}" ]]
}

@test "enban discovery saves the read rate of each stretch as CSV" {
  # Arrange
  linux_only
  blank_disc 250

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" --csv "${CSV}" <<<"disc.iso"

  # Assert
  local header rows second
  header="$(sed -n '1p' "${CSV}")"
  rows="$(grep -c '' "${CSV}")"
  second="$(awk -F , 'NR == 3 { print $1 "," $2 }' "${CSV}")"
  [[ "${status}" -eq 0 ]]
  [[ "${header}" == "sector,sectors,seconds,kib_per_second" ]]
  [[ "${rows}" -eq 85 ]]
  [[ "${second}" == "3,3" ]]
  [[ "${output}" == *"CSV          ${CSV}"* ]]
}

@test "enban discovery writes only the sectors asked for" {
  # Arrange
  linux_only
  blank_disc 128

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" --sectors 40 --csv "${CSV}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Written      40 sectors"* ]]
  [[ "${output}" == *"Read back    40 of 40 sectors"* ]]
}

@test "enban discovery names the first sector that reads back wrong" {
  # Arrange
  linux_only
  blank_disc 128
  disk_test_drive_flag corrupt

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" --csv "${CSV}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: sector 2 of the disc in ${DRIVE} does not read back as written." ]]
  [[ -s "${CSV}" ]]
}

@test "enban discovery names the first sector it cannot read" {
  # Arrange
  linux_only
  blank_disc 128
  disk_test_shim dd "case \" \$* \" in *\" skip=0 \"*|*\" skip=2 \"*|*\" skip=4 \"*) exec \"\${REAL}\" \"\$@\" ;; *\" if=\"*) exit 1 ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" --csv "${CSV}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Read back    6 of 128 sectors"* ]]
  [[ "${output}" == *"enban: sector 6 of the disc in ${DRIVE} cannot be read." ]]
}

@test "enban discovery keeps its runs under the data folder by default" {
  # Arrange
  linux_only
  blank_disc 64

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" <<<"disc.iso"

  # Assert
  local saved runs
  local -a found
  found=("${ENBAN_DATA}"/discovery/*.csv)
  saved="${#found[@]}"
  runs="$(cat "${ENBAN_DATA}/discovery/runs.tsv")"
  [[ "${status}" -eq 0 ]]
  [[ "${saved}" -eq 1 ]]
  [[ "${runs}" == *"${DRIVE}"$'\t'"DVD-R"$'\t'"64"$'\t'"auto"$'\t'"good"$'\t'"${ENBAN_DATA}/discovery/"*".csv" ]]
}

@test "enban discovery refuses a disc that is not blank" {
  # Arrange
  linux_only
  blank_disc 128
  local search_path
  search_path="$(disk_test_path)"
  dd if=/dev/urandom of="${WORK}/image.iso" bs=2048 count=10 2>/dev/null
  PATH="${search_path}" xorriso -as cdrecord dev="${DRIVE}" -dao "${WORK}/image.iso" >/dev/null 2>&1

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" --csv "${CSV}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: the disc in ${DRIVE} is not blank." ]]
}

@test "enban discovery refuses more sectors than the disc has" {
  # Arrange
  linux_only
  blank_disc 128

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" --sectors 500 --csv "${CSV}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: the disc in ${DRIVE} has 128 free sectors, not 500." ]]
}

@test "enban discovery never overwrites a CSV" {
  # Arrange
  linux_only
  blank_disc 128
  printf 'keep\n' >"${CSV}"

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" --csv "${CSV}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${CSV} already exists." ]]
}

@test "enban discovery writes nothing without the drive's name" {
  # Arrange
  linux_only
  blank_disc 128

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" --csv "${CSV}" <<<"wrong"

  # Assert
  local size
  size="$(wc -c <"${DISC}")"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: cancelled, nothing was written." ]]
  [[ "${size//[[:space:]]/}" -eq 0 ]]
}

@test "enban discovery says why the write failed" {
  # Arrange
  linux_only
  blank_disc 128
  disk_test_drive_flag fail_write

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" --csv "${CSV}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: the write to ${DRIVE} failed: -as cdrecord: Job could not be performed properly." ]]
}

@test "enban discovery draws its result with gum" {
  # Arrange
  linux_only
  blank_disc 64
  export ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log"

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" --csv "${CSV}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 0 ]]
  grep -qF -- "Done. ${DRIVE} passed discovery." "${WORK}/gum.log"
}

@test "enban discovery stops on macOS, where reading a drive is not supported yet" {
  # Arrange
  local drive=/dev/disk4

  # Act
  ENBAN_OS=Darwin run disk_test_run enban discovery --drive "${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: reading a drive is not supported on macOS yet, so discovery stops here." ]]
}

@test "enban discovery refuses a sector count that is not a number" {
  # Arrange
  local option=--sectors

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" "${option}" many </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --sectors must be a whole number from 1, got: many" ]]
}

@test "enban discovery without --drive stops with the usage hint" {
  # Arrange
  local command=discovery

  # Act
  run disk_test_run enban "${command}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: discovery needs --drive. run 'enban help' for usage." ]]
}
