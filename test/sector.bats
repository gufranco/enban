#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-sector.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  IMAGE="${WORK}/image.iso"
  dd if=/dev/zero of="${IMAGE}" bs=2048 count=40 2>/dev/null
  put 32768 '\001CD001\001'
  put $((32768 + 40)) 'FAMILY_2009'
  put $((32768 + 80)) '\050\000\000\000'
  put $((32768 + 132)) '\012\000\000\000'
  put $((32768 + 140)) '\023\000\000\000'
}

teardown() {
  rm -rf "${WORK}"
}

put() {
  printf '%b' "$2" | dd of="${IMAGE}" bs=1 seek="$1" conv=notrunc 2>/dev/null
}

@test "enban sector shows a sector as hex and text" {
  # Arrange
  local lba=16

  # Act
  run disk_test_run enban sector "${IMAGE}" --lba "${lba}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "LBA 16 of ${IMAGE}, user data 2048 bytes" ]]
  [[ "${lines[1]}" == "offset  00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f  text" ]]
  [[ "${lines[2]}" == "0000    01 43 44 30 30 31 01 00  00 00 00 00 00 00 00 00  .CD001.........." ]]
  [[ "${lines[4]}" == "0020    00 00 00 00 00 00 00 00  46 41 4d 49 4c 59 5f 32  ........FAMILY_2" ]]
  [[ "${lines[129]}" == "07f0    00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  ................" ]]
}

@test "enban sector decodes a primary volume descriptor" {
  # Arrange
  local lba=16

  # Act
  run disk_test_run enban sector "${IMAGE}" --lba "${lba}" </dev/null

  # Assert
  [[ "${output}" == *"Identifier   CD001, version 1"* ]]
  [[ "${output}" == *"Volume       FAMILY_2009"* ]]
  [[ "${output}" == *"Volume size  40 blocks of 2048"* ]]
  [[ "${output}" == *"Path table   10 bytes at LBA 19"* ]]
}

@test "enban sector shows the first sector by default and decodes nothing there" {
  # Arrange
  local image="${IMAGE}"

  # Act
  run disk_test_run enban sector "${image}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "LBA 0 of ${IMAGE}, user data 2048 bytes" ]]
  [[ "${output}" != *"Identifier"* ]]
}

@test "enban sector reads a sector of the disc in the drive" {
  # Arrange
  local search_path
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  : >"${WORK}/disc.iso"
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="stdio:${WORK}/disc.iso" -dao "${IMAGE}" >/dev/null 2>&1

  # Act
  run disk_test_run enban sector --drive "stdio:${WORK}/disc.iso" --lba 16 </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "LBA 16 of stdio:${WORK}/disc.iso, user data 2048 bytes" ]]
  [[ "${output}" == *"Volume       FAMILY_2009"* ]]
}

@test "enban sector stops past the end of the image" {
  # Arrange
  local lba=40

  # Act
  run disk_test_run enban sector "${IMAGE}" --lba "${lba}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: sector 40 is past the end of ${IMAGE}." ]]
}

@test "enban sector says when there is no image" {
  # Arrange
  local image="${WORK}/missing.iso"

  # Act
  run disk_test_run enban sector "${image}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no image at ${image}." ]]
}

@test "enban sector stops on macOS when asked for a disc" {
  # Arrange
  local drive=/dev/disk4

  # Act
  ENBAN_OS=Darwin run disk_test_run enban sector --drive "${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: reading a drive is not supported on macOS yet, so sector stops here." ]]
}

@test "enban sector refuses an LBA that is not a number" {
  # Arrange
  local option=--lba

  # Act
  run disk_test_run enban sector "${IMAGE}" "${option}" first </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --lba must be a whole number, got: first" ]]
}

@test "enban sector needs an image or a drive, not both" {
  # Arrange
  local image="${IMAGE}"

  # Act
  run disk_test_run enban sector "${image}" --drive /dev/sr0 </dev/null

  # Assert
  local none
  none="$(disk_test_run enban sector </dev/null 2>&1 || true)"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: sector takes an image or --drive, not both. run 'enban help' for usage." ]]
  [[ "${none}" == "enban: sector needs an image or --drive. run 'enban help' for usage." ]]
}

@test "write refuses --lba, which only sector takes" {
  # Arrange
  local option=--lba

  # Act
  run disk_test_run enban write "${IMAGE}" --drive /dev/sr0 "${option}" 4 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--lba' works only with sector. run 'enban help' for usage." ]]
}
