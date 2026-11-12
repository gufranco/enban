#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-write.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  IMAGE="${WORK}/image.iso"
  DISC="${WORK}/disc.iso"
  DRIVE="stdio:${DISC}"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=1024 2>/dev/null
  : >"${DISC}"
}

teardown() {
  rm -rf "${WORK}"
}

blank_dvd() {
  disk_test_drive 0011 "DVD-R sequential recording" "${1:-2298496}" 22160 11080
}

write_typing() {
  local answer="$1"
  shift
  printf '%s\n' "${answer}" | disk_test_run enban write "$@"
}

image_on_disc() {
  local bytes copy
  bytes="$(wc -c <"${IMAGE}")"
  copy="${WORK}/copy.iso"
  dd if="${DISC}" of="${copy}" bs=2048 count=$((bytes / 2048)) 2>/dev/null
  cmp -s "${copy}" "${IMAGE}"
}

foreign_image() {
  local search_path
  mkdir -p "${WORK}/files"
  head -c 70000 /dev/urandom >"${WORK}/files/photo.bin"
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as mkisofs -quiet -o "${IMAGE}" "${WORK}/files" 2>/dev/null
  disk_test_raw_bin "${IMAGE}" "$1"
}

@test "enban write converts an NRG image to ISO before it burns" {
  # Arrange
  blank_dvd
  foreign_image "${WORK}/disc.nrg"

  # Act
  run write_typing disc.iso "${WORK}/disc.nrg" --drive "${DRIVE}" --no-eject

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "Converting ${WORK}/disc.nrg to an ISO image before the burn."* ]]
  image_on_disc
}

@test "enban write removes the original image, not the converted one" {
  # Arrange
  blank_dvd
  foreign_image "${WORK}/disc.img"

  # Act
  run write_typing disc.iso "${WORK}/disc.img" --drive "${DRIVE}" --no-eject --delete-image

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Deleted ${WORK}/disc.img, as asked."* ]]
  [[ ! -e "${WORK}/disc.img" ]]
}

@test "enban write writes an IMG that is a plain ISO as it is" {
  # Arrange
  blank_dvd
  foreign_image "${WORK}/unused.img"
  cp -f "${IMAGE}" "${WORK}/plain.img"

  # Act
  run write_typing disc.iso "${WORK}/plain.img" --drive "${DRIVE}" --no-eject

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" != *"Converting"* ]]
  image_on_disc
}

@test "enban write stops when the image cannot be converted" {
  # Arrange
  blank_dvd
  foreign_image "${WORK}/disc.cdi"
  disk_test_shim iat "exit 1"

  # Act
  run write_typing disc.iso "${WORK}/disc.cdi" --drive "${DRIVE}" --no-eject

  # Assert
  local burned
  burned="$(sed -n 's/^burn=//p' "${WORK}/drive.state")"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: unable to convert ${WORK}/disc.cdi into "*"/image.iso." ]]
  [[ -z "${burned}" ]]
}

@test "enban write burns the image, verifies it and ejects the disc" {
  # Arrange
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is written, verified and ejected." ]]
  image_on_disc
}

@test "enban write asks for the drive's name before it writes" {
  # Arrange
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${output}" == *"Type disc.iso to write, or anything else to stop: "* ]]
}

@test "enban write writes nothing when the typed name is wrong" {
  # Arrange
  blank_dvd

  # Act
  run write_typing sr0 "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: stopped: nothing was written."* ]]
  [[ ! -s "${DISC}" ]]
}

@test "enban write refuses a disc that is not blank" {
  # Arrange
  blank_dvd
  local search_path
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="${DRIVE}" -dao "${IMAGE}" >/dev/null 2>&1
  local before
  before="$(wc -c <"${DISC}")"

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: the disc in ${DRIVE} is not blank." ]]
  local after
  after="$(wc -c <"${DISC}")"
  [[ "${after}" -eq "${before}" ]]
}

@test "enban write refuses an image larger than the free space" {
  # Arrange
  blank_dvd 512

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${IMAGE} needs 1024 sectors and the disc in ${DRIVE} has 512 free." ]]
}

@test "enban write skips the verify with --no-verify" {
  # Arrange
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --no-verify

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is written and ejected." ]]
}

@test "enban write leaves the tray closed with --no-eject" {
  # Arrange
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --no-eject

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is written and verified." ]]
}

@test "enban write says only written when it neither verifies nor ejects" {
  # Arrange
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --no-verify --no-eject

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is written." ]]
}

@test "enban write passes the speed to the burner" {
  # Arrange
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --speed 8

  # Assert
  [[ "${status}" -eq 0 ]]
  image_on_disc
}

@test "enban write reports a burn that fails" {
  # Arrange
  blank_dvd
  disk_test_drive_flag fail_write

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: the write to ${DRIVE} failed: -as cdrecord: Job could not be performed properly."* ]]
}

@test "enban write reports a disc that does not read back as the image" {
  # Arrange
  blank_dvd
  disk_test_drive_flag corrupt

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: the disc in ${DRIVE} does not match ${IMAGE}."* ]]
}

@test "enban write stops on macOS, where reading a drive is not supported yet" {
  # Arrange
  local drive=/dev/disk4

  # Act
  ENBAN_OS=Darwin run write_typing disk4 "${IMAGE}" --drive "${drive}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: on macOS name a drive like IODVDServices/0 or IOCompactDiscServices/0, or an image like stdio:disc.iso, so write cannot use ${drive}." ]]
}

@test "enban write refuses an image whose size is not whole sectors" {
  # Arrange
  printf 'x' >>"${IMAGE}"

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${IMAGE} is not a disc image: its size is not a whole number of 2048-byte sectors." ]]
}

@test "enban write refuses an image that does not exist" {
  # Arrange
  local missing="${WORK}/missing.iso"

  # Act
  run write_typing disc.iso "${missing}" --drive "${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no image at ${missing}." ]]
}

@test "enban write without an image stops with the usage hint" {
  # Arrange
  local option=--drive

  # Act
  run disk_test_run enban write "${option}" "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: write needs an image. run 'enban help' for usage." ]]
}

@test "enban write without --drive stops with the usage hint" {
  # Arrange
  local image="${IMAGE}"

  # Act
  run disk_test_run enban write "${image}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: write needs --drive. run 'enban help' for usage." ]]
}

@test "enban write takes one image only" {
  # Arrange
  local extra="${WORK}/other.iso"

  # Act
  run disk_test_run enban write "${IMAGE}" "${extra}" --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unexpected argument '${extra}'. run 'enban help' for usage." ]]
}

@test "enban write refuses a speed that is not a whole number" {
  # Arrange
  local speed=fast

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" --speed "${speed}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --speed must be a whole number of times, such as 8, got: fast" ]]
}

@test "enban info refuses an option that only write and read take" {
  # Arrange
  local option=--no-verify

  # Act
  run disk_test_run enban info --drive "${DRIVE}" "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--no-verify' works only with write, read and queue. run 'enban help' for usage." ]]
}

@test "enban info refuses an option that only write takes" {
  # Arrange
  local option=--no-eject

  # Act
  run disk_test_run enban info --drive "${DRIVE}" "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--no-eject' works only with write. run 'enban help' for usage." ]]
}

@test "enban write refuses --json, which only info takes" {
  # Arrange
  local option=--json

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--json' works only with info and features. run 'enban help' for usage." ]]
}

@test "enban write says so when the tray does not open" {
  # Arrange
  blank_dvd
  disk_test_drive_flag fail_eject

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"enban: warning: the disc is written, but ${DRIVE} did not open its tray."* ]]
  [[ "${output}" == *"Done. ${DRIVE} is written and verified." ]]
}

@test "enban write draws its result with gum" {
  # Arrange
  blank_dvd
  export ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log"

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is written, verified and ejected."* ]]
  grep -qF -- "Done. ${DRIVE} is written, verified and ejected." "${WORK}/gum.log"
}

@test "enban write --test runs the burn as a test and writes nothing" {
  # Arrange
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --test

  # Assert
  local burned
  burned="$(sed -n 's/^burn=//p' "${WORK}/drive.state")"
  [[ "${status}" -eq 0 ]]
  [[ "${burned}" == *" -dummy "* ]]
  [[ ! -s "${DISC}" ]]
  [[ "${output}" == *"Done. the test write to ${DRIVE} ran to the end, and nothing was written." ]]
}

@test "--test works only with write and discovery" {
  # Arrange
  mkdir -p "${WORK}/files"

  # Act
  run disk_test_run enban build "${WORK}/files" "${WORK}/out.iso" --test </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--test' works only with write and discovery. run 'enban help' for usage." ]]
}

@test "enban write --copies writes each copy on a fresh blank disc" {
  # Arrange
  blank_dvd
  disk_test_drive_flag swap

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --copies 2 --no-verify

  # Assert
  dd if="${DISC}.1" of="${WORK}/first.iso" bs=2048 count=1024 2>/dev/null
  dd if="${DISC}.2" of="${WORK}/second.iso" bs=2048 count=1024 2>/dev/null
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Copy 2 of 2: waiting for a blank disc in ${DRIVE}."* ]]
  cmp -s "${WORK}/first.iso" "${IMAGE}"
  cmp -s "${WORK}/second.iso" "${IMAGE}"
}

@test "enban write --copies stops when no blank disc arrives" {
  # Arrange
  blank_dvd

  # Act
  ENBAN_QUEUE_WAIT=1 run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --copies 2 --no-verify

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: no blank disc arrived in 1 seconds, so copy 2 of 2 was not written." ]]
}

@test "enban write --copies takes 1 to 100 and needs the tray to open" {
  # Arrange
  local drive="${DRIVE}"

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${drive}" --copies 101 </dev/null

  # Assert
  local zero eject
  zero="$(disk_test_run enban write "${IMAGE}" --drive "${drive}" --copies 0 </dev/null 2>&1 || true)"
  eject="$(disk_test_run enban write "${IMAGE}" --drive "${drive}" --copies 2 --no-eject </dev/null 2>&1 || true)"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --copies must be a whole number from 1 to 100, got: 101" ]]
  [[ "${zero}" == "enban: --copies must be a whole number from 1 to 100, got: 0" ]]
  [[ "${eject}" == "enban: --copies opens the tray between copies, so it cannot run with --no-eject." ]]
}

@test "enban write --delete-image removes the image once it is written" {
  # Arrange
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --delete-image --no-eject

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ ! -e "${IMAGE}" ]]
  [[ "${output}" == *"Deleted ${IMAGE}, as asked." ]]
}

@test "enban write --delete-image keeps the image of a test write" {
  # Arrange
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --delete-image --test

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -e "${IMAGE}" ]]
  [[ "${output}" == *"Kept ${IMAGE}, since a test write burns nothing." ]]
}

@test "enban write says when the image cannot be deleted" {
  # Arrange
  local user
  user="$(id -u)"
  [[ "${user}" != 0 ]] || skip "root deletes from a read-only folder"
  blank_dvd
  mkdir -p "${WORK}/kept"
  cp "${IMAGE}" "${WORK}/kept/image.iso"
  chmod 555 "${WORK}/kept"

  # Act
  run write_typing disc.iso "${WORK}/kept/image.iso" --drive "${DRIVE}" --delete-image --no-eject

  # Assert
  chmod 755 "${WORK}/kept"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: every copy is written, but ${WORK}/kept/image.iso could not be deleted." ]]
}

@test "--copies and --delete-image work only with write" {
  # Arrange
  mkdir -p "${WORK}/files"

  # Act
  run disk_test_run enban build "${WORK}/files" "${WORK}/out.iso" --copies 2 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--copies' works only with write. run 'enban help' for usage." ]]
}

@test "enban write passes track at once and an open disc to the burner" {
  # Arrange
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --mode tao --no-finalize --no-eject

  # Assert
  local burned
  burned="$(sed -n 's/^burn=//p' "${WORK}/drive.state")"
  [[ "${status}" -eq 0 ]]
  [[ "${burned}" == *" -tao -multi "* ]]
  image_on_disc
}

@test "enban write --opc calibrates the laser before it burns" {
  # Arrange
  blank_dvd
  disk_test_raw

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --opc --no-eject

  # Assert
  local sent
  sent="$(cat "${WORK}/sg_raw.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "${DISC} 54 01 00 00 00 00 00 00 00 00" ]]
  [[ "${output}" == *"Calibrating the laser power of ${DRIVE}."* ]]
  image_on_disc
}

@test "enban write --opc stops when the drive refuses to calibrate" {
  # Arrange
  blank_dvd
  disk_test_raw
  disk_test_drive_flag raw_fail

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --opc --no-eject

  # Assert
  local burned
  burned="$(sed -n 's/^burn=//p' "${WORK}/drive.state")"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: the drive refused the command: SCSI Status: Check Condition" ]]
  [[ -z "${burned}" ]]
}

@test "enban write --opc needs sg_raw" {
  # Arrange
  blank_dvd
  local farm
  farm="$(disk_test_farm sg_raw)"

  # Act
  run disk_test_run_path "${farm}" enban write "${IMAGE}" --drive "${DRIVE}" --opc </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --opc needs sg_raw from sg3-utils to calibrate the laser. install it and try again." ]]
}

@test "enban write reads sao as disc at once" {
  # Arrange
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --mode sao --no-eject

  # Assert
  local burned
  burned="$(sed -n 's/^burn=//p' "${WORK}/drive.state")"
  [[ "${status}" -eq 0 ]]
  [[ "${burned}" == *" -dao "* ]]
}

@test "enban write --mode takes dao or tao and only write takes it" {
  # Arrange
  local mode=raw96

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" --mode "${mode}" </dev/null

  # Assert
  local other
  other="$(disk_test_run enban erase --drive "${DRIVE}" --opc </dev/null 2>&1 || true)"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --mode takes dao or tao, got: raw96" ]]
  [[ "${other}" == "enban: option '--opc' works only with write. run 'enban help' for usage." ]]
}
