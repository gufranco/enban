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
  [[ "${first}" == "dev=${DRIVE} f=${OUT} sectors=0-40 speed=32" ]]
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

written_cd() {
  cp -f "${IMAGE}" "${WORK}/mac.disc"
  disk_test_mac_drive CD "CD-R" complete 40 0
}

appendable_dvd() {
  cp -f "${IMAGE}" "${WORK}/mac.disc"
  disk_test_mac_drive DVD "DVD+R" incomplete/appendable 40 2295000
  disk_test_mac_set sessions 2
}

@test "enban tray load, lock and unlock run cdrecord on a macOS drive" {
  # Arrange
  blank_dvd

  # Act
  run disk_test_run enban tray --drive "${DRIVE}" lock </dev/null

  # Assert
  local sent_last
  sent_last="$(sed -n '$p' "${WORK}/cdrecord.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent_last}" == "dev=${DRIVE} -lock" ]]
  [[ "${output}" == "Done. the tray of ${DRIVE} is locked until it is unlocked or the drive restarts." ]]
}

@test "enban tray unlock loads through cdrecord, which frees the tray" {
  # Arrange
  blank_dvd

  # Act
  run disk_test_run enban tray --drive "${DRIVE}" unlock </dev/null

  # Assert
  local sent_last
  sent_last="$(sed -n '$p' "${WORK}/cdrecord.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent_last}" == "dev=${DRIVE} -load" ]]
  [[ "${output}" == "Done. the tray of ${DRIVE} is unlocked." ]]
}

@test "enban tray load closes a macOS drive's tray" {
  # Arrange
  blank_dvd

  # Act
  run disk_test_run enban tray --drive "${DRIVE}" load </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "Done. the tray of ${DRIVE} is closed and its disc loaded." ]]
}

@test "enban tray names cdrecord's refusal on a macOS drive" {
  # Arrange
  blank_dvd
  disk_test_mac_set fail_load 1

  # Act
  run disk_test_run enban tray --drive "${DRIVE}" load </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the drive refused the command: Cannot load media." ]]
}

@test "enban rezero and sync reach a macOS drive through cdrecord" {
  # Arrange
  blank_dvd
  disk_test_run enban rezero --drive "${DRIVE}" </dev/null >"${WORK}/rezero.out"

  # Act
  run disk_test_run enban sync --drive "${DRIVE}" </dev/null

  # Assert
  local rezero sent
  rezero="$(<"${WORK}/rezero.out")"
  sent="$(grep -c -- '-load\|-abort' "${WORK}/cdrecord.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${rezero}" == "Done. ${DRIVE} moved its head back to the start of the disc." ]]
  [[ "${output}" == "Done. ${DRIVE} wrote its cache to the disc." ]]
  [[ "${sent}" == "2" ]]
}

@test "enban close fixates the session of a macOS disc and keeps it open" {
  # Arrange
  appendable_dvd

  # Act
  run disk_test_run enban close --drive "${DRIVE}" <<<"${DRIVE}"

  # Assert
  local sent_last
  sent_last="$(sed -n '$p' "${WORK}/cdrecord.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent_last}" == "dev=${DRIVE} -fix -tao -multi" ]]
  [[ "${output}" == *"Done. the session on ${DRIVE} is closed." ]]
}

@test "enban close --finalize fixates a macOS disc for good" {
  # Arrange
  appendable_dvd

  # Act
  run disk_test_run enban close --drive "${DRIVE}" --finalize <<<"${DRIVE}"

  # Assert
  local sent_last
  sent_last="$(sed -n '$p' "${WORK}/cdrecord.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent_last}" == "dev=${DRIVE} -fix -tao" ]]
  [[ "${output}" == *"Done. the disc in ${DRIVE} is finalized." ]]
}

@test "enban close --track says cdrecord cannot close one track on macOS" {
  # Arrange
  appendable_dvd

  # Act
  run disk_test_run enban close --drive "${DRIVE}" --track <<<"${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: close --track needs sg_raw; on macOS cdrecord closes a session or the disc, never one track alone." ]]
}

@test "enban close names cdrecord's refusal on a macOS drive" {
  # Arrange
  appendable_dvd
  disk_test_mac_set fail_fix 1

  # Act
  run disk_test_run enban close --drive "${DRIVE}" <<<"${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: the drive refused the command: Cannot fixate disk." ]]
}

@test "enban features lists a macOS drive's features from cdrecord" {
  # Arrange
  blank_dvd
  disk_test_mac_set features "002b:1 0040:0 9999:0"

  # Act
  run disk_test_run enban features --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "0x002b  DVD+R                                    current" ]]
  [[ "${lines[1]}" == "0x0040  BD read                                  supported" ]]
  [[ "${lines[2]}" == "0x9999  unknown feature                          supported" ]]
}

@test "enban features names cdrecord's refusal on a macOS drive" {
  # Arrange
  blank_dvd
  disk_test_run enban info --drive "${DRIVE}" </dev/null >/dev/null
  disk_test_shim cdrecord "case \" \$* \" in *\" -x \"*) exit 255 ;; esac; exec sh '${ENBAN_TESTS_DIR}/cdrecord.sh' '${WORK}/mac.state' \"\$@\""

  # Act
  run disk_test_run enban features --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the drive refused the command: cdrecord could not read the feature list." ]]
}

@test "enban speed sets a macOS drive's read speed through readcd in CD units" {
  # Arrange
  written_dvd

  # Act
  run disk_test_run enban speed --drive "${DRIVE}" 4 </dev/null

  # Assert
  local sent
  sent="$(<"${WORK}/readcd.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "dev=${DRIVE} speed=32 sectors=0-0 f=/dev/null" ]]
  [[ "${output}" == "Done. ${DRIVE} reads at 4x." ]]
}

@test "enban speed max asks readcd for the fastest speed" {
  # Arrange
  written_dvd

  # Act
  run disk_test_run enban speed --drive "${DRIVE}" max </dev/null

  # Assert
  local sent
  sent="$(<"${WORK}/readcd.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "dev=${DRIVE} speed=400 sectors=0-0 f=/dev/null" ]]
  [[ "${output}" == "Done. ${DRIVE} reads at its fastest." ]]
}

@test "enban speed names readcd's refusal on a macOS drive" {
  # Arrange
  written_dvd
  disk_test_mac_set fail_read 1

  # Act
  run disk_test_run enban speed --drive "${DRIVE}" 4 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the drive refused the command: Cannot open SCSI driver." ]]
}

@test "enban region says no macOS command reaches the region" {
  # Arrange
  written_dvd

  # Act
  run disk_test_run enban region --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: region needs sg_raw; no macOS command reads or sets a drive's DVD region." ]]
}

@test "enban write --opc leaves the calibration to cdrecord on macOS" {
  # Arrange
  blank_dvd

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" --opc <<<"${DRIVE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"cdrecord calibrates the laser power of ${DRIVE} itself before the write."* ]]
}

@test "enban sector --subchannel reads one raw sector of a macOS CD through readcd" {
  # Arrange
  written_cd

  # Act
  run disk_test_run enban sector --drive "${DRIVE}" --subchannel --lba 16 </dev/null

  # Assert
  local sent
  sent="$(<"${WORK}/readcd.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "dev=${DRIVE} -clone sectors=16-17 f="*" retries=0" ]]
  [[ "${lines[${#lines[@]} - 1]}" == "Q channel    track 01, index 01, 00:00:16 in the track, 00:02:16 on the disc" ]]
}

@test "enban sector --raw shows a macOS CD sector without its subchannel" {
  # Arrange
  written_cd

  # Act
  run disk_test_run enban sector --drive "${DRIVE}" --raw --lba 3 </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"raw 2352"* ]]
  [[ "${output}" != *"Q channel"* ]]
}

@test "enban sector --raw names readcd's refusal on a macOS drive" {
  # Arrange
  written_cd
  disk_test_mac_set fail_after 0

  # Act
  run disk_test_run enban sector --drive "${DRIVE}" --raw --lba 3 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the drive refused the command: readcd could not read sector 3." ]]
}

@test "enban read --ccd copies a macOS CD through readcd -clone" {
  # Arrange
  written_cd
  local raw="${WORK}/copy.img"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${raw}" --ccd </dev/null

  # Assert
  local main_size sub_size clones
  main_size="$(wc -c <"${raw}")"
  sub_size="$(wc -c <"${WORK}/copy.sub")"
  clones="$(grep -c -- '-clone sectors=0-40' "${WORK}/readcd.log")"
  dd if="${raw}" bs=1 skip=$((5 * 2352 + 16)) count=2048 2>/dev/null >"${WORK}/user.bin"
  dd if="${IMAGE}" bs=2048 skip=5 count=1 2>/dev/null >"${WORK}/want.bin"
  [[ "${status}" -eq 0 ]]
  [[ "${main_size//[[:space:]]/}" == "94080" ]]
  [[ "${sub_size//[[:space:]]/}" == "3840" ]]
  [[ "${clones}" == "2" ]]
  cmp -s "${WORK}/user.bin" "${WORK}/want.bin"
  [[ -s "${WORK}/copy.ccd" ]]
  [[ "${output}" == *"Done. ${DRIVE} is read into ${raw} and verified." ]]
}

@test "enban read --ccd stops at a sector readcd could not read on macOS" {
  # Arrange
  written_cd
  disk_test_mac_set bad 7

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/copy.img" --ccd </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: 1 sectors of ${DRIVE} could not be read; --ignore-errors keeps them as zeros." ]]
}

@test "enban read --ccd --ignore-errors keeps an unreadable macOS sector as zeros" {
  # Arrange
  written_cd
  disk_test_mac_set bad 7

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/copy.img" --ccd --ignore-errors </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"enban: warning: 1 sectors of ${DRIVE} could not be read and are zeros in ${WORK}/copy.img."* ]]
  [[ "${output}" == *"Done. ${DRIVE} is read into ${WORK}/copy.img." ]]
}

@test "enban read --ccd says when readcd cannot read a macOS CD" {
  # Arrange
  written_cd
  disk_test_mac_set fail_after 0

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/copy.img" --ccd </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to read ${DRIVE} into ${WORK}/copy.img." ]]
}

@test "enban read --ccd reports a macOS copy it cannot read back" {
  # Arrange
  written_cd
  disk_test_mac_set fail_after 1

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/copy.img" --ccd </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the copy in ${WORK}/copy.img does not match the disc in ${DRIVE}." ]]
}

@test "enban booktype reaches a macOS disc through the node drutil names" {
  # Arrange
  appendable_dvd
  disk_test_shim drutil "printf '           Type: DVD+R           Name: /dev/disk4\\n'"
  disk_test_shim dvd+rw-booktype "printf '%s\\n' \"\$*\" >>'${WORK}/booktype.log'; printf 'Book type: DVD+R\\n'"

  # Act
  run disk_test_run enban booktype --drive "${DRIVE}" </dev/null

  # Assert
  local sent
  sent="$(<"${WORK}/booktype.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "-inq /dev/disk4" ]]
  [[ "${output}" == "Book type: DVD+R" ]]
}

@test "enban booktype says when drutil names no disc on macOS" {
  # Arrange
  appendable_dvd
  disk_test_shim drutil "exit 1"
  disk_test_shim dvd+rw-booktype "exit 0"

  # Act
  run disk_test_run enban booktype --drive "${DRIVE}" dvd-rom <<<"${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: drutil names no disc device for ${DRIVE}, so its book type cannot be reached." ]]
}
