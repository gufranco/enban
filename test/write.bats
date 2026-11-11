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

linux_only() {
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
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

@test "enban write burns the image, verifies it and ejects the disc" {
  # Arrange
  linux_only
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
  linux_only
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${output}" == *"Type disc.iso to write, or anything else to stop: "* ]]
}

@test "enban write writes nothing when the typed name is wrong" {
  # Arrange
  linux_only
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
  linux_only
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
  linux_only
  blank_dvd 512

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${IMAGE} needs 1024 sectors and the disc in ${DRIVE} has 512 free." ]]
}

@test "enban write skips the verify with --no-verify" {
  # Arrange
  linux_only
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --no-verify

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is written and ejected." ]]
}

@test "enban write leaves the tray closed with --no-eject" {
  # Arrange
  linux_only
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --no-eject

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is written and verified." ]]
}

@test "enban write says only written when it neither verifies nor ejects" {
  # Arrange
  linux_only
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --no-verify --no-eject

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is written." ]]
}

@test "enban write passes the speed to the burner" {
  # Arrange
  linux_only
  blank_dvd

  # Act
  run write_typing disc.iso "${IMAGE}" --drive "${DRIVE}" --speed 8

  # Assert
  [[ "${status}" -eq 0 ]]
  image_on_disc
}

@test "enban write reports a burn that fails" {
  # Arrange
  linux_only
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
  linux_only
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
  [[ "${output}" == "enban: reading a drive is not supported on macOS yet, so write stops here." ]]
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
  [[ "${output}" == "enban: option '--json' works only with info. run 'enban help' for usage." ]]
}

@test "enban write says so when the tray does not open" {
  # Arrange
  linux_only
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
  linux_only
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
  linux_only
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
