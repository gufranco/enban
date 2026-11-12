#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-ttab.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_TEST_GUM APP_PATH
  IMAGE="${WORK}/image.iso"
  DISC="${WORK}/disc.iso"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=64 2>/dev/null
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

written() {
  local search_path
  disk_test_drive "$1" "$2" 2298496 22160
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="stdio:${DISC}" -dao "${IMAGE}" >/dev/null 2>&1
}

@test "the Tools tab lists the drive and image tools with the focus on Erase disc" {
  # Arrange
  local keys='7q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Drive"*"> Erase disc"*"Close"*"Capabilities"*"Image"*"Checksum"*"Mount"* ]]
}

@test "the focus stops at both ends of the tool list" {
  # Arrange
  local keys
  keys="7\\033[A$(printf '\\033[B%.0s' {1..20})q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Sync cache"* ]]
}

@test "Enter on Erase disc opens the erase panel and space picks the method" {
  # Arrange
  local keys='7\n q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Erase disc"*"Method     full"* ]]
  [[ "${shown}" == *"Everything on the disc is lost."* ]]
}

@test "Escape leaves the erase panel for the tool list" {
  # Arrange
  local keys='7\n\033[Zq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Erase disc"*"quick or full"* ]]
}

@test "the erase panel needs a drive" {
  # Arrange
  local keys='7\n\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to erase."* ]]
}

@test "the erase panel erases a rewritable disc after the drive's name" {
  # Arrange
  written 0013 "DVD-RW restricted overwrite"
  answers disc.iso

  # Act
  run on_terminal_in_steps '7\n\n' 'is erased' 'q' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Result"*"Done. stdio:${DISC} is erased."* ]]
}

@test "the erase panel touches nothing without the drive's name" {
  # Arrange
  written 0013 "DVD-RW restricted overwrite"
  cp "${DISC}" "${WORK}/before.iso"
  answers wrong

  # Act
  run on_terminal '7\n\nq' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Nothing was erased."* ]]
  cmp -s "${WORK}/before.iso" "${DISC}"
}

@test "the erase panel shows why a disc cannot be erased" {
  # Arrange
  written 0011 "DVD-R sequential recording"
  answers disc.iso

  # Act
  run on_terminal_in_steps '7\n\n' 'the result says why' 'q' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"is a DVD-R, which cannot be erased."* ]]
}

@test "c cancels an erase" {
  # Arrange
  written 0013 "DVD-RW restricted overwrite"
  disk_test_drive_flag slow
  answers disc.iso

  # Act
  run on_terminal_in_steps '7\n\n' 'Press c to cancel' 'cq' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Cancelled while erasing. The disc may be unusable."* ]]
}

@test "c cancels a checksum" {
  # Arrange
  disk_test_shim shasum "sleep 43; exec \"\${REAL}\" \"\$@\""
  disk_test_shim sha256sum "sleep 43; exec \"\${REAL}\" \"\$@\""
  answers "${IMAGE}"

  # Act
  run on_terminal_in_steps "7$(printf '\\033[B%.0s' {1..12})\\n" 'Press c to cancel' 'cq'

  # Assert
  local shown left
  shown="$(last_frame)"
  left="$(pgrep -f 'sleep 43' || true)"
  [[ "${shown}" == *"Cancelled while checking. Nothing changed."* ]]
  [[ -z "${left}" ]]
}

@test "Tray loads, locks and unlocks through the drive" {
  # Arrange
  written 0011 "DVD-R sequential recording"
  disk_test_raw
  answers lock

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..4})\\nq" --drive "stdio:${DISC}"

  # Assert
  local shown sent
  shown="$(last_frame)"
  sent="$(cat "${WORK}/sg_raw.log")"
  [[ "${sent}" == "${DISC} 1e 00 00 00 01 00" ]]
  [[ "${shown}" == *"Done. the tray of stdio:${DISC} is locked"* ]]
}

@test "Tray says what it takes" {
  # Arrange
  written 0011 "DVD-R sequential recording"
  answers open

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..4})\\nq" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"The tray takes eject, load, lock or unlock."* ]]
}

@test "ReZero moves the head back through the drive" {
  # Arrange
  written 0011 "DVD-R sequential recording"
  disk_test_raw

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..15})\\nq" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"stdio:${DISC} moved its head back to the start of the disc."* ]]
}

@test "Sync cache writes the drive's cache" {
  # Arrange
  written 0011 "DVD-R sequential recording"
  disk_test_raw

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..16})\\nq" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"stdio:${DISC} wrote its cache to the disc."* ]]
}

@test "ReZero and Sync cache need a drive" {
  # Arrange
  local keys
  keys="7$(printf '\\033[B%.0s' {1..15})\\n\\033[B\\nq"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(screen)"
  [[ "${shown}" == *"There is no drive to move the head of."* ]]
  [[ "${shown}" == *"There is no drive to sync the cache of."* ]]
}

@test "Tray ejects the disc" {
  # Arrange
  written 0011 "DVD-R sequential recording"

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..4})\\nq" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"The tray of stdio:${DISC} is open."* ]]
}

@test "Tray says when the tray did not open" {
  # Arrange
  written 0011 "DVD-R sequential recording"
  disk_test_drive_flag fail_eject

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..4})\\nq" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"The tray of stdio:${DISC} did not open."* ]]
}

@test "Tray needs a drive" {
  # Arrange
  local keys
  keys="7$(printf '\\033[B%.0s' {1..4})\\nq"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to eject."* ]]
}

@test "Capabilities lists the kinds of disc the drive handles" {
  # Arrange
  written 0011 "DVD-R sequential recording"
  disk_test_drive_profiles 0011 0009 000a 0011 001a

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..5})\\nq" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Capabilities"*"CD-R"*"CD-RW"*"DVD-R"*"DVD+RW"* ]]
}

@test "Capabilities says when no drive is chosen and Enter goes back" {
  # Arrange
  local keys
  keys="7$(printf '\\033[B%.0s' {1..5})\\n"

  # Act
  run on_terminal_in_steps "${keys}" 'The drive reports nothing' '\nq'

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"The drive reports nothing it can read or write."* ]]
  [[ "${final}" == *"> Capabilities"* ]]
}

@test "Checksum prints the checksums of the chosen image" {
  # Arrange
  local line
  line="$(openssl dgst -sha256 "${IMAGE}")"
  answers "${IMAGE}"

  # Act
  run on_terminal_in_steps "7$(printf '\\033[B%.0s' {1..12})\\n" 'is checked' 'q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Result"*"SHA-256  ${line##* }"* ]]
}

@test "Checksum of the disc needs a drive" {
  # Arrange
  answers ""

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..12})\\nq"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to check."* ]]
}

@test "the Tools tab starts nothing while a read runs" {
  # Arrange
  local call='DISK_APP_JOB=running DISK_APP_JOB_KIND=read DISK_APP_JOB_PID=1; disk_tools_tab_erase; printf "%s|%s|%s\n" "${DISK_APP_JOB_KIND}" "${DISK_APP_JOB_PID}" "${DISK_APP_STATUS}"'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "read|1|A read is running. Press c on its tab to cancel it first." ]]
}

@test "the Tools tab ignores other keys" {
  # Arrange
  local keys='7zq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Erase disc"* ]]
}

sector_image() {
  dd if=/dev/zero of="${IMAGE}" bs=2048 count=20 2>/dev/null
  printf '\001CD001\001' | dd of="${IMAGE}" bs=1 seek=32768 conv=notrunc 2>/dev/null
  printf 'FAMILY' | dd of="${IMAGE}" bs=1 seek=32808 conv=notrunc 2>/dev/null
}

sector_keys() {
  local moves
  moves="$(printf '\\033[B%.0s' 1 2 3 4 5 6)"
  printf '7%s\\n%s' "${moves}" "$1"
}

@test "the Sector viewer asks for an image when no drive is chosen" {
  # Arrange
  sector_image
  answers "${IMAGE}"
  local keys
  keys="$(sector_keys q)"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Sector viewer   LBA 0 of ${IMAGE}"* ]]
  [[ "${shown}" == *"0000    00 00 00 00"* ]]
}

@test "the Sector viewer steps through sectors and pages and decodes LBA 16" {
  # Arrange
  sector_image
  answers "${IMAGE}" 16
  local keys
  keys="$(sector_keys '\033[C\033[Dg\033[B\033[B\033[Aq')"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"LBA 1 of ${IMAGE}"* ]]
  [[ "${final}" == *"LBA 16 of ${IMAGE}"*"0100    "*"Volume       FAMILY"* ]]
}

@test "the Sector viewer says when the sector is past the end and Escape goes back" {
  # Arrange
  sector_image
  answers "${IMAGE}" 999
  local keys
  keys="$(sector_keys 'g')"

  # Act
  run on_terminal_in_steps "${keys}" 'past the end' '\033[Zq'

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"Sector 999 is past the end of ${IMAGE}."* ]]
  [[ "${final}" == *"> Sector viewer"* ]]
}

@test "the Sector viewer stays on the list without an image and refuses a word for an LBA" {
  # Arrange
  sector_image
  answers "" "${IMAGE}" first
  local keys
  keys="$(sector_keys '\ngq')"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"The LBA must be a whole number."* ]]
}

@test "the Sector viewer reads the disc in the drive" {
  # Arrange
  written 0011 "DVD-R sequential recording"
  local keys
  keys="$(sector_keys q)"

  # Act
  run on_terminal "${keys}" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Sector viewer   LBA 0 of stdio:${DISC}"* ]]
}

tool_keys() {
  local moves="" count=0
  while [[ "${count}" -lt "$1" ]]; do
    moves="${moves}\\033[B"
    count=$((count + 1))
  done
  printf '7%s\\n%s' "${moves}" "$2"
}

iso_session() {
  local search_path
  disk_test_drive "$1" "$2" 2298496 22160
  disk_test_raw
  search_path="$(disk_test_path)"
  mkdir -p "${WORK}/files"
  cp "${IMAGE}" "${WORK}/files/data.bin"
  PATH="${search_path}" xorriso -outdev "stdio:${DISC}" -volid FILES -map "${WORK}/files" / -commit >/dev/null 2>&1
}

@test "Close closes the session after the drive's name" {
  # Arrange
  iso_session 0011 "DVD-R sequential recording"
  answers session disc.iso
  local keys
  keys="$(tool_keys 1 q)"

  # Act
  run on_terminal "${keys}" --drive "stdio:${DISC}"

  # Assert
  local shown sent
  shown="$(last_frame)"
  sent="$(cat "${WORK}/sg_raw.log")"
  [[ "${shown}" == *"Done. the session on stdio:${DISC} is closed."* ]]
  [[ "${sent}" == *"5b 01 02 00"* ]]
}

@test "Close closes the last track after the drive's name" {
  # Arrange
  iso_session 0011 "DVD-R sequential recording"
  printf 'last_track=3\n' >>"${WORK}/drive.state"
  answers track disc.iso
  local keys
  keys="$(tool_keys 1 q)"

  # Act
  run on_terminal "${keys}" --drive "stdio:${DISC}"

  # Assert
  local shown sent
  shown="$(last_frame)"
  sent="$(cat "${WORK}/sg_raw.log")"
  [[ "${shown}" == *"Done. track 3 on stdio:${DISC} is closed."* ]]
  [[ "${sent}" == *"5b 01 01 00 00 03 00"* ]]
}

@test "Close finalizes the disc and stops at the first refusal" {
  # Arrange
  iso_session 0011 "DVD-R sequential recording"
  answers disc disc.iso session wrong
  local keys
  keys="$(tool_keys 1 '\nq')"

  # Act
  run on_terminal "${keys}" --drive "stdio:${DISC}"

  # Assert
  local shown sent
  shown="$(screen)"
  sent="$(cat "${WORK}/sg_raw.log")"
  [[ "${shown}" == *"Done. the disc in stdio:${DISC} is finalized."* ]]
  [[ "${shown}" == *"Nothing was touched."* ]]
  [[ "${sent}" == *"5b 01 04 00"* ]]
}

@test "Close needs a drive and says why it cannot close" {
  # Arrange
  answers session
  local keys
  keys="$(tool_keys 1 q)"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to close."* ]]
}

@test "Close says the disc has no session to close" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  disk_test_raw
  answers session
  local keys
  keys="$(tool_keys 1 q)"

  # Act
  run on_terminal "${keys}" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Stopped: the disc in stdio:${DISC} is blank, so there is no session to close."* ]]
}

@test "Read speed sets the speed and refuses words" {
  # Arrange
  iso_session 0011 "DVD-R sequential recording"
  answers 4 fast
  local keys
  keys="$(tool_keys 3 '\nq')"

  # Act
  run on_terminal "${keys}" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(screen)"
  [[ "${shown}" == *"Done. stdio:${DISC} reads at 4x, 5540 kB/s."* ]]
  [[ "${shown}" == *"The speed must be a whole number of times or max."* ]]
}

@test "Region shows the region, then changes it after the drive's name" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  disk_test_raw
  printf 'rpc=%s\n' '\0000\0006\0000\0000\0124\0375\0001\0000' >>"${WORK}/drive.state"
  answers "" 1 disc.iso 3 wrong 12
  local keys
  keys="$(tool_keys 7 '\n\n\nq')"

  # Act
  run on_terminal "${keys}" --drive "stdio:${DISC}"

  # Assert
  local shown sent
  shown="$(screen)"
  sent="$(cat "${WORK}/sg_raw.log")"
  [[ "${shown}" == *"Region 2, 4 changes left, RPC Phase II."* ]]
  [[ "${shown}" == *"Done. stdio:${DISC} is set to region 1."* ]]
  [[ "${shown}" == *"Nothing was touched."* ]]
  [[ "${shown}" == *"The region must be a number from 1 to 8."* ]]
  [[ "${sent}" == *"a3 00"* ]]
}

@test "Book type changes a DVD+R and refuses an unknown type" {
  # Arrange
  disk_test_drive 001b "DVD+R" 2298496 22160
  disk_test_shim id "case \"\$1\" in -u) printf '0\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  disk_test_shim dvd+rw-booktype "printf '%s\\n' \"\$*\" >>'${WORK}/booktype.log'"
  answers dvd-rom disc.iso hd-dvd
  local keys
  keys="$(tool_keys 2 '\nq')"

  # Act
  run on_terminal "${keys}" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(screen)"
  [[ "${shown}" == *"Done. the disc in stdio:${DISC} reads as DVD-ROM."* ]]
  [[ "${shown}" == *"The book type must be dvd-rom, dvd+r or dvd+rw."* ]]
}

@test "the drive tools need a drive" {
  # Arrange
  local keys
  keys="$(tool_keys 3 '\033[A\n\033[B\033[B\033[B\033[B\033[B\nq')"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(screen)"
  [[ "${shown}" == *"There is no drive to set the speed of."* ]]
  [[ "${shown}" == *"There is no drive to change the book type of."* ]]
  [[ "${shown}" == *"There is no drive to read the region of."* ]]
}

@test "Book type says it applies only to DVD+R and DVD+RW" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  disk_test_shim id "case \"\$1\" in -u) printf '0\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  disk_test_shim dvd+rw-booktype "exit 0"
  answers dvd-rom
  local keys
  keys="$(tool_keys 2 q)"

  # Act
  run on_terminal "${keys}" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Stopped: the book type applies to DVD+R and DVD+RW discs"* ]]
}

@test "Region says when the drive refuses" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  disk_test_raw
  disk_test_drive_flag raw_fail
  answers ""
  local keys
  keys="$(tool_keys 7 q)"

  # Act
  run on_terminal "${keys}" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"The drive refused the command: SCSI Status: Check Condition"* ]]
}

@test "Create CUE writes a sheet for the WAV files of a folder" {
  # Arrange
  mkdir -p "${WORK}/album"
  printf 'RIFF\044\000\000\000WAVEfmt \020\000\000\000\001\000\002\000\104\254\000\000\020\261\002\000\004\000\020\000data\000\000\000\000' >"${WORK}/album/01.wav"
  cp "${WORK}/album/01.wav" "${WORK}/album/02.wav"
  answers "${WORK}/album" "${WORK}/album/album.cue" "${WORK}/nowhere" ""
  local keys
  keys="$(tool_keys 9 '\nq')"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown sheet
  shown="$(screen)"
  sheet="$(cat "${WORK}/album/album.cue")"
  [[ "${shown}" == *"Done. ${WORK}/album/album.cue lists 2 tracks."* ]]
  [[ "${shown}" == *"No WAV files in ${WORK}/nowhere."* ]]
  [[ "${sheet}" == *'FILE "02.wav" WAVE'* ]]
}

@test "Convert turns an image into an ISO as a job" {
  # Arrange
  local search_path
  mkdir -p "${WORK}/files"
  printf 'hi\n' >"${WORK}/files/a.txt"
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as mkisofs -quiet -o "${WORK}/real.iso" "${WORK}/files" 2>/dev/null
  answers "${WORK}/real.iso" "${WORK}/out.iso"
  local keys
  keys="$(tool_keys 10 '')"

  # Act
  run on_terminal_in_steps "${keys}" 'the result says why' '\nq'

  # Assert
  local shown
  shown="$(screen)"
  [[ "${shown}" == *"is already an ISO image, so it needs no conversion."* ]]
}

@test "Convert asks for both files" {
  # Arrange
  answers "${IMAGE}" ""
  local keys
  keys="$(tool_keys 10 q)"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Convert"* ]]
}

@test "m shows raw 2352-byte sectors in the Sector viewer" {
  # Arrange
  dd if=/dev/zero of="${WORK}/disc.bin" bs=2352 count=3 2>/dev/null
  answers "${WORK}/disc.bin"
  local keys
  keys="$(sector_keys 'm\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[Bq')"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"LBA 0 of ${WORK}/disc.bin, raw 2352 bytes"* ]]
  [[ "${shown}" == *"0920    "* ]]
}

@test "s adds the subchannel and its Q channel to the Sector viewer" {
  # Arrange
  dd if=/dev/zero of="${WORK}/disc.img" bs=2352 count=3 2>/dev/null
  head -c 288 /dev/zero >"${WORK}/disc.sub"
  answers "${WORK}/disc.img"
  local keys
  keys="$(sector_keys 's\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[Bq')"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"LBA 0 of ${WORK}/disc.img, raw 2352 bytes"* ]]
  [[ "${shown}" == *"Subchannel P-W, 96 bytes"* ]]
  [[ "${shown}" == *"Q channel    mode 0"* ]]
}

@test "c cancels a convert" {
  # Arrange
  disk_test_shim iat "sleep 47"
  printf 'not an iso' >"${WORK}/disc.nrg"
  answers "${WORK}/disc.nrg" "${WORK}/out.iso"
  local keys
  keys="$(tool_keys 10 '')"

  # Act
  run on_terminal_in_steps "${keys}" 'Press c to cancel' 'cq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Cancelled while converting. No ISO was written."* ]]
}

@test "Volume label relabels an ISO image" {
  # Arrange
  mkdir -p "${WORK}/files"
  printf 'hello\n' >"${WORK}/files/a.txt"
  disk_test_run enban build "${WORK}/files" "${WORK}/label.iso" --fs iso9660 </dev/null >/dev/null
  answers "${WORK}/label.iso" "holiday"
  local keys
  keys="$(tool_keys 11 'q')"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown label
  shown="$(last_frame)"
  label="$(dd if="${WORK}/label.iso" bs=1 skip=$((16 * 2048 + 40)) count=7 2>/dev/null)"
  [[ "${shown}" == *"Done. ${WORK}/label.iso is labelled HOLIDAY."* ]]
  [[ "${label}" == "HOLIDAY" ]]
}

@test "Layer break says an image that fits one layer needs none" {
  # Arrange
  printf 'CD001' >"${WORK}/magic"
  head -c 65536 /dev/zero >"${WORK}/small.iso"
  dd if="${WORK}/magic" of="${WORK}/small.iso" bs=1 seek=32769 conv=notrunc 2>/dev/null
  answers "${WORK}/small.iso"
  local keys
  keys="$(tool_keys 13 'q')"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"fits on one layer, so it needs no layer break."* ]]
}

@test "Mount says why an image did not mount and unmounts a folder" {
  # Arrange
  head -c 65536 /dev/zero >"${WORK}/blank.img"
  mkdir -p "${WORK}/empty"
  [[ "${ENBAN_TEST_OS}" == "Darwin" ]] || disk_test_shim udisksctl "exec sh $(printf '%q' "${ENBAN_TESTS_DIR}/udisksctl.sh") $(printf '%q' "${WORK}") \"\$@\""
  answers "${WORK}/blank.img" "${WORK}/empty"
  local keys
  keys="$(tool_keys 14 '')"

  # Act
  run on_terminal_in_steps "${keys}" 'Unable to mount' '\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Unable to unmount ${WORK}/empty. close what uses it and try again."* ]]
}

@test "Speed memory lists the remembered speeds and Enter goes back" {
  # Arrange
  export ENBAN_DATA="${WORK}/data"
  mkdir -p "${ENBAN_DATA}"
  printf 'ASUS SDRW-08U9M-U\tMCC 03RG20\t8\n' >"${ENBAN_DATA}/speeds.tsv"
  local keys
  keys="$(tool_keys 8 '')"

  # Act
  run on_terminal_in_steps "${keys}" 'MCC 03RG20' '\nq'

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"Speed memory"*"ASUS SDRW-08U9M-U"*"MCC 03RG20"*"8x"* ]]
  [[ "${final}" == *"> Speed memory"* ]]
}

@test "Speed memory says when nothing is remembered" {
  # Arrange
  export ENBAN_DATA="${WORK}/data"
  local keys
  keys="$(tool_keys 8 'q')"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"No speeds remembered yet."* ]]
}
