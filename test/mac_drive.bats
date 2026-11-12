#!/usr/bin/env bats
# shellcheck disable=SC2016

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-mac.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  DRIVE=IODVDServices/0
  IMAGE="${WORK}/image.iso"
  OUT="${WORK}/copy.iso"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=40 2>/dev/null
}

teardown() {
  rm -rf "${WORK}"
}

blank_dvd() {
  disk_test_mac_drive DVD "DVD-R sequential recording" empty 0 2298496
}

written_dvd() {
  cp -f "${IMAGE}" "${WORK}/mac.disc"
  disk_test_mac_drive DVD "DVD-R sequential recording" complete 40 0
}

sent() {
  sed -n "$1p" "${WORK}/$2.log"
}

@test "enban info reads a macOS drive through cdrecord" {
  # Arrange
  blank_dvd

  # Act
  run disk_test_run enban info --drive "${DRIVE}" --json </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "{\"drive\":\"${DRIVE}\",\"vendor\":\"HL-DT-ST\",\"product\":\"DVDRAM GH24NSB0\",\"revision\":\"LK00\",\"profile\":\"DVD-R sequential recording\",\"profile_code\":\"0011\",\"status\":\"blank\",\"sessions\":0,\"data_sectors\":0,\"free_sectors\":2298496,\"write_speeds\":[{\"bytes_per_second\":22160000,\"x\":16},{\"bytes_per_second\":11080000,\"x\":8}],\"media\":[\"DVD-R\",\"CD-R\"]}" ]]
}

@test "enban info counts a closed disc's sessions and data" {
  # Arrange
  written_dvd

  # Act
  run disk_test_run enban info --drive "${DRIVE}" --json </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"\"status\":\"closed\",\"sessions\":1,\"data_sectors\":40,\"free_sectors\":0,"* ]]
}

@test "enban info leaves the open session out of an appendable disc's count" {
  # Arrange
  disk_test_mac_drive DVD "DVD+R" incomplete/appendable 40 2295000
  disk_test_mac_set sessions 2

  # Act
  run disk_test_run enban info --drive "${DRIVE}" --json </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"\"profile\":\"DVD+R\",\"profile_code\":\"001b\",\"status\":\"appendable\",\"sessions\":1,\"data_sectors\":40,"* ]]
}

@test "enban info names a CD's speeds in CD units" {
  # Arrange
  disk_test_mac_drive CD "CD-R" empty 0 359844

  # Act
  run disk_test_run enban info --drive "${DRIVE}" --json </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"\"profile_code\":\"0009\""*"\"write_speeds\":[{\"bytes_per_second\":22160000,\"x\":125},{\"bytes_per_second\":11080000,\"x\":62}]"* ]]
}

@test "enban info names a Blu-ray's speeds in BD units" {
  # Arrange
  disk_test_mac_drive BD "BD-R sequential recording" empty 0 12219392

  # Act
  run disk_test_run enban info --drive "${DRIVE}" --json </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"\"profile_code\":\"0041\""*"\"write_speeds\":[{\"bytes_per_second\":22160000,\"x\":4},{\"bytes_per_second\":11080000,\"x\":2}]"* ]]
}

@test "enban info says when the macOS drive holds no disc" {
  # Arrange
  disk_test_mac_drive DVD "DVD-R sequential recording" none 0 0

  # Act
  run disk_test_run enban info --drive "${DRIVE}" --json </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"\"profile\":\"\",\"profile_code\":\"\",\"status\":\"empty\","* ]]
}

@test "enban info names a disc status it cannot use and a profile it does not know" {
  # Arrange
  disk_test_mac_drive DVD "HD DVD-R" illegal 0 0

  # Act
  run disk_test_run enban info --drive "${DRIVE}" --json </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"\"profile\":\"HD DVD-R\",\"profile_code\":\"\",\"status\":\"unreadable\","* ]]
  [[ "${output}" == *"\"media\":[\"HD\",\"CD-R\"]"* ]]
}

@test "enban info stops when cdrecord cannot open the drive" {
  # Arrange
  blank_dvd
  disk_test_mac_set fail_prcap 1

  # Act
  run disk_test_run enban info --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to read the drive ${DRIVE}." ]]
}

@test "enban info stops when the macOS drive is not ready" {
  # Arrange
  blank_dvd
  disk_test_mac_set fail_minfo 1

  # Act
  run disk_test_run enban info --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to read the drive ${DRIVE}." ]]
}

@test "a macOS drive needs cdrtools" {
  # Arrange
  blank_dvd
  local farm
  farm="$(disk_test_farm readcd)"

  # Act
  run disk_test_run_path "${farm}" enban info --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: a drive named ${DRIVE} needs cdrecord and readcd from cdrtools. install cdrtools and try again." ]]
}

@test "enban write burns a macOS drive through cdrecord after its whole name is typed" {
  # Arrange
  blank_dvd

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" --speed 8 <<<"${DRIVE}"

  # Assert
  local burn eject
  burn="$(sent 3 cdrecord)"
  eject="$(sent 4 cdrecord)"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "Type ${DRIVE} to write, or anything else to stop: "*"Done. ${DRIVE} is written, verified and ejected." ]]
  [[ "${burn}" == "-v dev=${DRIVE} -dao speed=8 ${IMAGE}" ]]
  [[ "${eject}" == "dev=${DRIVE} -eject" ]]
  cmp -s "${IMAGE}" "${WORK}/mac.disc"
}

@test "enban write on a macOS drive refuses the short name" {
  # Arrange
  blank_dvd

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" <<<"0"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: stopped: nothing was written." ]]
  [[ ! -s "${WORK}/mac.disc" ]]
}

@test "enban write names the cdrecord failure on a macOS drive" {
  # Arrange
  blank_dvd
  disk_test_mac_set fail_write 1

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" <<<"${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: the write to ${DRIVE} failed: A write error occurred." ]]
}

@test "enban write says when the macOS drive did not open its tray" {
  # Arrange
  blank_dvd
  disk_test_mac_set fail_eject 1

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" <<<"${DRIVE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"enban: warning: the disc is written, but ${DRIVE} did not open its tray."* ]]
}

@test "enban read copies a macOS drive through readcd at the asked speed" {
  # Arrange
  written_dvd

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" --speed 4 </dev/null

  # Assert
  local first
  first="$(sent 1 readcd)"
  [[ "${status}" -eq 0 ]]
  [[ "${first}" == "dev=${DRIVE} f=${OUT} sectors=0-40 speed=4" ]]
  [[ "${output}" == *"Done. ${DRIVE} is read into ${OUT} and verified." ]]
  cmp -s "${IMAGE}" "${OUT}"
}

@test "enban read --ignore-errors counts what readcd could not read on a macOS drive" {
  # Arrange
  written_dvd
  disk_test_mac_set bad 7

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" --ignore-errors </dev/null

  # Assert
  local salvage
  salvage="$(sent 2 readcd)"
  [[ "${status}" -eq 0 ]]
  [[ "${salvage}" == "dev=${DRIVE} f=${OUT} sectors=0-40 -noerror retries=0" ]]
  [[ "${output}" == *"enban: warning: 1 sectors of ${DRIVE} could not be read and are zeros in ${OUT}."* ]]
}

@test "enban verify reads a macOS drive and finds where it stops reading" {
  # Arrange
  written_dvd
  disk_test_mac_set bad 30

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Readable     30 of 40 sectors"* ]]
  [[ "${output}" == *"enban: 10 sectors of the disc in ${DRIVE} could not be read, from sector 30." ]]
}

@test "enban checksum hashes the disc in a macOS drive" {
  # Arrange
  written_dvd
  local sums want
  sums="$(sha256sum "${IMAGE}" 2>/dev/null || shasum -a 256 "${IMAGE}")"
  want="${sums%% *}"

  # Act
  run disk_test_run enban checksum --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"SHA-256  ${want}"* ]]
}

@test "enban erase blanks a macOS drive through cdrecord" {
  # Arrange
  disk_test_mac_drive DVD "DVD-RW sequential recording" complete 40 0
  cp -f "${IMAGE}" "${WORK}/mac.disc"

  # Act
  run disk_test_run enban erase --drive "${DRIVE}" --full <<<"${DRIVE}"

  # Assert
  local blank
  blank="$(sent 3 cdrecord)"
  [[ "${status}" -eq 0 ]]
  [[ "${blank}" == "dev=${DRIVE} blank=all" ]]
  [[ ! -s "${WORK}/mac.disc" ]]
}

@test "enban erase names the cdrecord failure on a macOS drive" {
  # Arrange
  disk_test_mac_drive DVD "DVD-RW sequential recording" complete 40 0
  disk_test_mac_set fail_blank 1

  # Act
  run disk_test_run enban erase --drive "${DRIVE}" <<<"${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: the erase of ${DRIVE} failed: Cannot blank disk, aborting." ]]
}

@test "enban sector reads one sector of a macOS drive" {
  # Arrange
  written_dvd

  # Act
  run disk_test_run enban sector --drive "${DRIVE}" --lba 3 </dev/null

  # Assert
  local first
  first="$(sent 1 readcd)"
  [[ "${status}" -eq 0 ]]
  [[ "${first}" == "dev=${DRIVE} f="*" sectors=3-4" ]]
}

@test "enban discovery writes and reads back a macOS drive" {
  # Arrange
  disk_test_mac_drive DVD "DVD-R sequential recording" empty 0 64

  # Act
  run disk_test_run enban discovery --drive "${DRIVE}" <<<"${DRIVE}"

  # Assert
  local burn
  burn="$(grep -- '-dao' "${WORK}/cdrecord.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${burn}" == "-v dev=${DRIVE} -dao tsize=131072 -" ]]
  [[ "${output}" == *"Read back    64 of 64 sectors"* ]]
}

@test "the readcd summary takes the time readcd measured" {
  # Arrange
  printf 'addr:       16 cnt: 16\rRead 32.00 kB at 128.0 kB/sec.\nTime total: 0.250sec\n' >"${WORK}/readcd.err"
  local call="DISK_DRIVE='${DRIVE}'; disk_mac_summary '${WORK}/readcd.err'"

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == $'16+0 records in\n16+0 records out\n32768 bytes copied, 0.250 s' ]]
}
