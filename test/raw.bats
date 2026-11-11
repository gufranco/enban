#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-raw.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  DISC="${WORK}/disc.iso"
  DRIVE="stdio:${DISC}"
  IMAGE="${WORK}/image.iso"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=512 2>/dev/null
  : >"${DISC}"
}

teardown() {
  rm -rf "${WORK}"
}

drive_with() {
  local search_path
  disk_test_drive "$1" "$2" 2298496 22160
  disk_test_raw
  if [[ "${3:-}" == written ]]; then
    search_path="$(disk_test_path)"
    mkdir -p "${WORK}/files"
    cp "${IMAGE}" "${WORK}/files/data.bin"
    PATH="${search_path}" xorriso -outdev "${DRIVE}" -volid FILES -map "${WORK}/files" / -commit >/dev/null 2>&1
  fi
}

sent() {
  sed -n "$1p" "${WORK}/sg_raw.log"
}

@test "enban close closes the session after the drive's name" {
  # Arrange
  drive_with 0011 "DVD-R sequential recording" written

  # Act
  run disk_test_run enban close --drive "${DRIVE}" <<<"disc.iso"

  # Assert
  local command
  command="$(sent 1)"
  [[ "${status}" -eq 0 ]]
  [[ "${command}" == "${DISC} 5b 01 02 00 00 00 00 00 00 00" ]]
  [[ "${output}" == *"Done. the session on ${DRIVE} is closed." ]]
}

@test "enban close --finalize closes the whole disc" {
  # Arrange
  drive_with 0011 "DVD-R sequential recording" written

  # Act
  run disk_test_run enban close --drive "${DRIVE}" --finalize <<<"disc.iso"

  # Assert
  local command
  command="$(sent 1)"
  [[ "${status}" -eq 0 ]]
  [[ "${command}" == "${DISC} 5b 01 04 00 00 00 00 00 00 00" ]]
  [[ "${output}" == *"Done. the disc in ${DRIVE} is finalized." ]]
}

@test "enban close sends nothing without the drive's name" {
  # Arrange
  drive_with 0011 "DVD-R sequential recording" written

  # Act
  run disk_test_run enban close --drive "${DRIVE}" <<<"wrong"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: cancelled, nothing was touched." ]]
  [[ ! -e "${WORK}/sg_raw.log" ]]
}

@test "enban close refuses a disc that is not appendable" {
  # Arrange
  drive_with 0011 "DVD-R sequential recording"

  # Act
  run disk_test_run enban close --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: the disc in ${DRIVE} is blank, so there is no session to close." ]]
}

@test "enban close says what the drive answered when it refuses" {
  # Arrange
  drive_with 0011 "DVD-R sequential recording" written
  disk_test_drive_flag raw_fail

  # Act
  run disk_test_run enban close --drive "${DRIVE}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: the drive refused the command: SCSI Status: Check Condition" ]]
}

@test "enban speed sets the read speed in kB/s for the disc's kind" {
  # Arrange
  drive_with 0011 "DVD-R sequential recording" written

  # Act
  run disk_test_run enban speed --drive "${DRIVE}" 4 </dev/null

  # Assert
  local command
  command="$(sent 1)"
  [[ "${status}" -eq 0 ]]
  [[ "${command}" == "${DISC} bb 00 15 a4 ff ff 00 00 00 00 00 00" ]]
  [[ "${output}" == *"Done. ${DRIVE} reads at 4x, 5540 kB/s." ]]
}

@test "enban speed counts a CD's 1x as 177 kB/s and max as the drive's fastest" {
  # Arrange
  drive_with 0009 "CD-R" written

  # Act
  run disk_test_run enban speed --drive "${DRIVE}" 8 </dev/null

  # Assert
  local first second
  first="$(sent 1)"
  ENBAN_OS="" disk_test_run enban speed --drive "${DRIVE}" max </dev/null
  second="$(sent 2)"
  [[ "${first}" == "${DISC} bb 00 05 88 ff ff 00 00 00 00 00 00" ]]
  [[ "${second}" == "${DISC} bb 00 ff ff ff ff 00 00 00 00 00 00" ]]
}

@test "enban speed refuses a speed that is not a number or max" {
  # Arrange
  local speed=fast

  # Act
  run disk_test_run enban speed --drive "${DRIVE}" "${speed}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the speed must be a whole number of times or max, got: fast" ]]
}

@test "enban region shows the drive's region and the changes left" {
  # Arrange
  drive_with 0011 "DVD-R sequential recording"
  printf 'rpc=%s\n' '\0000\0006\0000\0000\0124\0375\0001\0000' >>"${WORK}/drive.state"

  # Act
  run disk_test_run enban region --drive "${DRIVE}" </dev/null

  # Assert
  local command
  command="$(sent 1)"
  [[ "${status}" -eq 0 ]]
  [[ "${command}" == "-r 8 -o "*" ${DISC} a4 00 00 00 00 00 00 00 00 08 08 00" ]]
  [[ "${lines[0]}" == "Region          2" ]]
  [[ "${lines[1]}" == "Changes left    4" ]]
  [[ "${lines[2]}" == "Vendor resets   2" ]]
  [[ "${lines[3]}" == "Scheme          RPC Phase II" ]]
}

@test "enban region says when no region is set" {
  # Arrange
  drive_with 0011 "DVD-R sequential recording"
  printf 'rpc=%s\n' '\0000\0006\0000\0000\0005\0377\0000\0000' >>"${WORK}/drive.state"

  # Act
  run disk_test_run enban region --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${lines[0]}" == "Region          none set" ]]
  [[ "${lines[3]}" == "Scheme          RPC Phase I" ]]
}

@test "enban region --set spends a change after the drive's name" {
  # Arrange
  drive_with 0011 "DVD-R sequential recording"
  printf 'rpc=%s\n' '\0000\0006\0000\0000\0124\0375\0001\0000' >>"${WORK}/drive.state"

  # Act
  run disk_test_run enban region --drive "${DRIVE}" --set 1 <<<"disc.iso"

  # Assert
  local command
  command="$(sent 2)"
  [[ "${status}" -eq 0 ]]
  [[ "${command}" == "-s 8 -i "*" ${DISC} a3 00 00 00 00 00 00 00 00 08 06 00" ]]
  [[ "${output}" == *"This uses one of the 4 changes left; at zero the region is fixed for good."* ]]
  [[ "${output}" == *"Done. ${DRIVE} is set to region 1." ]]
}

@test "enban region --set refuses when no changes are left" {
  # Arrange
  drive_with 0011 "DVD-R sequential recording"
  printf 'rpc=%s\n' '\0000\0006\0000\0000\0200\0375\0001\0000' >>"${WORK}/drive.state"

  # Act
  run disk_test_run enban region --drive "${DRIVE}" --set 1 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: stopped: ${DRIVE} has no region changes left."* ]]
}

@test "enban region --set refuses a region outside 1 to 8" {
  # Arrange
  local region=9

  # Act
  run disk_test_run enban region --drive "${DRIVE}" --set "${region}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --set takes a region from 1 to 8, got: 9" ]]
}

@test "enban sector --raw reads 2352 bytes with READ CD" {
  # Arrange
  drive_with 0009 "CD-R" written

  # Act
  run disk_test_run enban sector --drive "${DRIVE}" --raw --lba 3 </dev/null

  # Assert
  local command
  command="$(sent 1)"
  [[ "${status}" -eq 0 ]]
  [[ "${command}" == "-r 2352 -o "*" ${DISC} be 00 00 00 00 03 00 00 01 f8 00 00" ]]
  [[ "${lines[0]}" == "LBA 3 of ${DRIVE}, raw 2352 bytes" ]]
  [[ "${lines[2]}" == "0000    00 ff ff ff ff ff ff ff  ff ff ff 00 00 02 00 01  ................" ]]
}

@test "enban sector --raw reads a 2352-byte sector of a BIN image" {
  # Arrange
  dd if=/dev/zero of="${WORK}/disc.bin" bs=2352 count=4 2>/dev/null
  printf 'MARK' | dd of="${WORK}/disc.bin" bs=1 seek=$((2352 * 2 + 16)) conv=notrunc 2>/dev/null

  # Act
  run disk_test_run enban sector "${WORK}/disc.bin" --raw --lba 2 </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "LBA 2 of ${WORK}/disc.bin, raw 2352 bytes" ]]
  [[ "${lines[3]}" == "0010    4d 41 52 4b 00 00 00 00  00 00 00 00 00 00 00 00  MARK............" ]]
}

@test "the raw drive commands stop on macOS" {
  # Arrange
  local drive=/dev/disk4

  # Act
  ENBAN_OS=Darwin run disk_test_run enban region --drive "${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: reading a drive is not supported on macOS yet, so region stops here." ]]
}

@test "the raw drive commands need sg_raw" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  local farm
  farm="$(disk_test_farm sg_raw)"

  # Act
  run disk_test_run_path "${farm}" enban region --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: region needs sg_raw from sg3-utils. install it and try again." ]]
}

@test "close, speed and region need --drive" {
  # Arrange
  local command=close

  # Act
  run disk_test_run enban "${command}" </dev/null

  # Assert
  local speed region
  speed="$(disk_test_run enban speed 4 </dev/null 2>&1 || true)"
  region="$(disk_test_run enban region </dev/null 2>&1 || true)"
  [[ "${output}" == "enban: close needs --drive. run 'enban help' for usage." ]]
  [[ "${speed}" == "enban: speed needs --drive. run 'enban help' for usage." ]]
  [[ "${region}" == "enban: region needs --drive. run 'enban help' for usage." ]]
}

@test "speed needs a speed" {
  # Arrange
  local drive="${DRIVE}"

  # Act
  run disk_test_run enban speed --drive "${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: speed needs a speed, such as 4 or max. run 'enban help' for usage." ]]
}

@test "enban speed counts a Blu-ray's 1x as 4496 kB/s" {
  # Arrange
  drive_with 0041 "BD-R sequential recording" written

  # Act
  run disk_test_run enban speed --drive "${DRIVE}" 2 </dev/null

  # Assert
  local command
  command="$(sent 1)"
  [[ "${status}" -eq 0 ]]
  [[ "${command}" == "${DISC} bb 00 23 20 ff ff 00 00 00 00 00 00" ]]
}
