#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-drive.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
}

teardown() {
  rm -rf "${WORK}"
}

linux_only() {
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
}

blank_dvd() {
  : >"${WORK}/disc.iso"
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
}

written_dvd() {
  mkdir -p "${WORK}/files"
  printf 'hello\n' >"${WORK}/files/hello.txt"
  local search_path
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -outdev "stdio:${WORK}/disc.iso" -volid FILES -map "${WORK}/files" / -commit >/dev/null 2>&1
}

@test "enban info --json describes a blank DVD-R in the drive" {
  # Arrange
  linux_only
  blank_dvd
  local drive="stdio:${WORK}/disc.iso"

  # Act
  run disk_test_run enban info --drive "${drive}" --json </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "{\"drive\":\"${drive}\",\"vendor\":\"YOYODYNE\",\"product\":\"WARP DRIVE\",\"revision\":\"FX01\",\"profile\":\"DVD-R sequential recording\",\"profile_code\":\"0011\",\"status\":\"blank\",\"sessions\":0,\"data_sectors\":0,\"free_sectors\":2298496,\"write_speeds\":[{\"bytes_per_second\":22160000,\"x\":16.0},{\"bytes_per_second\":11080000,\"x\":8.0}],\"media\":[]}" ]]
}

@test "enban info names a written DVD-R as appendable with one session" {
  # Arrange
  linux_only
  written_dvd
  local drive="stdio:${WORK}/disc.iso"

  # Act
  run disk_test_run enban info --drive "${drive}" --json </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"\"status\":\"appendable\",\"sessions\":1,"* ]]
}

@test "enban info prints the disc as readable lines" {
  # Arrange
  linux_only
  blank_dvd
  local drive="stdio:${WORK}/disc.iso"

  # Act
  run disk_test_run enban info --drive="${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "Drive     ${drive}, YOYODYNE WARP DRIVE FX01" ]]
  [[ "${lines[1]}" == "Disc      DVD-R sequential recording, blank" ]]
  [[ "${lines[2]}" == "Sessions  0, 0 data sectors" ]]
  [[ "${lines[3]}" == "Free      2298496 sectors, 4.7 GB" ]]
  [[ "${lines[4]}" == "Speeds    16.0x, 8.0x" ]]
  [[ "${lines[5]}" == "Media     none reported" ]]
}

@test "enban info lists every kind of disc the drive handles" {
  # Arrange
  linux_only
  blank_dvd
  disk_test_drive_profiles 0011 0009 000a 0011 0013 0014 001a 0041 0042
  local drive="stdio:${WORK}/disc.iso"

  # Act
  run disk_test_run enban info --drive "${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[5]}" == "Media     CD-R, CD-RW, DVD-R, DVD-RW, DVD+RW, BD-R" ]]
}

@test "enban info --json lists the kinds of disc the drive handles" {
  # Arrange
  linux_only
  blank_dvd
  disk_test_drive_profiles 0011 0009 0011
  local drive="stdio:${WORK}/disc.iso"

  # Act
  run disk_test_run enban info --drive "${drive}" --json </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *",\"media\":[\"CD-R\",\"DVD-R\"]}" ]]
}

@test "enban info stops when the drive cannot be read" {
  # Arrange
  linux_only
  local drive="stdio:${WORK}/missing/disc.iso"

  # Act
  run disk_test_run enban info --drive "${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to read the drive ${drive}." ]]
}

@test "enban info names the macOS gap instead of guessing" {
  # Arrange
  local drive=/dev/disk4

  # Act
  ENBAN_OS=Darwin run disk_test_run enban info --drive "${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: reading a drive is not supported on macOS yet, so info stops here." ]]
}

@test "enban info without --drive stops with the usage hint" {
  # Arrange
  local command=info

  # Act
  run disk_test_run enban "${command}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: info needs --drive. run 'enban help' for usage." ]]
}

@test "enban info --drive without a value stops with the usage hint" {
  # Arrange
  local option=--drive

  # Act
  run disk_test_run enban info "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--drive' needs a value. run 'enban help' for usage." ]]
}

@test "enban info rejects an unknown option" {
  # Arrange
  local option=--fast

  # Act
  run disk_test_run enban info "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unknown option '--fast'. run 'enban help' for usage." ]]
}

@test "enban info --json=yes says the flag takes no value" {
  # Arrange
  local option=--json=yes

  # Act
  run disk_test_run enban info "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--json' takes no value. run 'enban help' for usage." ]]
}

@test "enban info rejects an option it does not know with a value" {
  # Arrange
  local option=--volume=DATA

  # Act
  run disk_test_run enban info "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unknown option '--volume'. run 'enban help' for usage." ]]
}

@test "enban info rejects a stray argument" {
  # Arrange
  local extra=/dev/sr1

  # Act
  run disk_test_run enban info --drive /dev/sr0 "${extra}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unexpected argument '/dev/sr1'. run 'enban help' for usage." ]]
}

@test "enban info reads a plain image file with no profile code and no speeds" {
  # Arrange
  linux_only
  : >"${WORK}/plain.iso"
  local drive="stdio:${WORK}/plain.iso"

  # Act
  run disk_test_run enban info --drive "${drive}" --json </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"\"profile\":\"stdio file, overwriteable\",\"profile_code\":\"\",\"status\":\"blank\","* ]]
  [[ "${output}" == *"\"write_speeds\":[],\"media\":[]}" ]]
}

@test "enban info says when the drive reports no speeds" {
  # Arrange
  linux_only
  : >"${WORK}/plain.iso"
  local drive="stdio:${WORK}/plain.iso"

  # Act
  run disk_test_run enban info --drive "${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[4]}" == "Speeds    none reported" ]]
}

@test "enban info draws the disc as a table with gum" {
  # Arrange
  linux_only
  blank_dvd
  local drive="stdio:${WORK}/disc.iso"

  # Act
  ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log" run disk_test_run enban info --drive "${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Field"*"Value"* ]]
  [[ "${output}" == *"DVD-R sequential recording, blank"* ]]
}

media_states() {
  local line
  for line in "is blank" "is written , is appendable" "is written , is closed" "is not present" \
    "is not recognizable" "is unsuitable , is POW formatted"; do
    disk_test_call eval "disk_drive_fields 'Media status : ${line}'; printf '%s\n' \"\${DISK_DRIVE_STATUS}\""
  done
}

@test "every media status xorriso prints maps to one state" {
  # Arrange
  local expected=$'blank\nappendable\nclosed\nempty\nunreadable\nunreadable'

  # Act
  run media_states

  # Assert
  [[ "${output}" == "${expected}" ]]
}

@test "enban info rejects a short option" {
  # Arrange
  local option=-x

  # Act
  run disk_test_run enban info "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unknown option '-x'. run 'enban help' for usage." ]]
}
