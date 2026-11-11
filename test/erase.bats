#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-erase.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  IMAGE="${WORK}/image.iso"
  DISC="${WORK}/disc.iso"
  DRIVE="stdio:${DISC}"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=200 2>/dev/null
  : >"${DISC}"
}

teardown() {
  rm -rf "${WORK}"
}

written() {
  local search_path
  disk_test_drive "$1" "$2" 2298496 22160
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="${DRIVE}" -dao "${IMAGE}" >/dev/null 2>&1
}

byte_at() {
  local value
  value="$(od -An -tx1 -j "$1" -N 1 "${DISC}")"
  printf '%s\n' "${value//[[:space:]]/}"
}

@test "enban erase blanks a rewritable disc after the drive's name is typed" {
  # Arrange
  written 0013 "DVD-RW restricted overwrite"
  local name="${DISC##*/}"
  local wanted
  wanted="$(byte_at 300000)"

  # Act
  run disk_test_run enban erase --drive "${DRIVE}" <<<"${name}"

  # Assert
  local status_line kept search_path toc
  search_path="$(disk_test_path)"
  toc="$(PATH="${search_path}" xorriso -outdev "${DRIVE}" -toc 2>/dev/null)"
  status_line="$(grep 'Media status' <<<"${toc}")"
  kept="$(byte_at 300000)"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is erased." ]]
  local mode
  mode="$(sed -n 's/^blanked=//p' "${WORK}/drive.state")"
  [[ "${status_line}" == *"is blank"* ]]
  [[ "${kept}" == "${wanted}" ]]
  [[ "${mode}" == "fast" ]]
}

@test "enban erase --full asks the drive for a full blank" {
  # Arrange
  written 0013 "DVD-RW restricted overwrite"
  local name="${DISC##*/}"

  # Act
  run disk_test_run enban erase --drive "${DRIVE}" --full <<<"${name}"

  # Assert
  local mode
  mode="$(sed -n 's/^blanked=//p' "${WORK}/drive.state")"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is erased in full." ]]
  [[ "${mode}" == "all" ]]
}

@test "enban erase touches nothing when the typed name is wrong" {
  # Arrange
  written 0013 "DVD-RW restricted overwrite"
  cp "${DISC}" "${WORK}/before.iso"

  # Act
  run disk_test_run enban erase --drive "${DRIVE}" <<<"wrong"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: cancelled, nothing was touched." ]]
  cmp -s "${WORK}/before.iso" "${DISC}"
}

@test "enban erase refuses a disc that cannot be erased" {
  # Arrange
  written 0011 "DVD-R sequential recording"

  # Act
  run disk_test_run enban erase --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: the disc in ${DRIVE} is a DVD-R, which cannot be erased." ]]
}

@test "enban erase leaves a blank disc alone" {
  # Arrange
  disk_test_drive 0013 "DVD-RW restricted overwrite" 2298496 22160

  # Act
  run disk_test_run enban erase --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: the disc in ${DRIVE} is already blank." ]]
}

@test "enban erase says why the drive failed" {
  # Arrange
  written 0013 "DVD-RW restricted overwrite"
  disk_test_drive_flag fail_blank
  local name="${DISC##*/}"

  # Act
  run disk_test_run enban erase --drive "${DRIVE}" <<<"${name}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: the erase of ${DRIVE} failed: -blank: Job could not be performed properly." ]]
}

@test "enban erase draws its result with gum" {
  # Arrange
  written 0013 "DVD-RW restricted overwrite"
  export ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log"
  local name="${DISC##*/}"

  # Act
  run disk_test_run enban erase --drive "${DRIVE}" <<<"${name}"

  # Assert
  [[ "${status}" -eq 0 ]]
  grep -qF -- "Done. ${DRIVE} is erased." "${WORK}/gum.log"
}

@test "enban erase stops on macOS, where reading a drive is not supported yet" {
  # Arrange
  local drive=/dev/disk4

  # Act
  ENBAN_OS=Darwin run disk_test_run enban erase --drive "${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: reading a drive is not supported on macOS yet, so erase stops here." ]]
}

@test "enban erase without --drive stops with the usage hint" {
  # Arrange
  local option=--full

  # Act
  run disk_test_run enban erase "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: erase needs --drive. run 'enban help' for usage." ]]
}

@test "write refuses --full, which only erase takes" {
  # Arrange
  local option=--full

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--full' works only with erase. run 'enban help' for usage." ]]
}
