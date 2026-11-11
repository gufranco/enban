#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-wtab.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_TEST_GUM APP_PATH
  IMAGE="${WORK}/image.iso"
  DISC="${WORK}/disc.iso"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=64 2>/dev/null
  : >"${DISC}"
  export ENBAN_TEST_GUM_ANSWERS="${WORK}/answers"
}

teardown() {
  rm -rf "${WORK}"
}

linux_only() {
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
}

answers() {
  printf '%s\n' "$@" >"${ENBAN_TEST_GUM_ANSWERS}"
}

blank_dvd() {
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
}

image_on_disc() {
  local copy="${WORK}/copy.iso"
  dd if="${DISC}" of="${copy}" bs=2048 count=64 2>/dev/null
  cmp -s "${copy}" "${IMAGE}"
}

@test "the Write tab burns the chosen image, verifies it and shows the result" {
  # Arrange
  linux_only
  blank_dvd
  answers "${IMAGE}" disc.iso

  # Act
  run on_terminal_in_steps '1\nw' 'is written, verified and ejected' 'q' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"Result"*"Done. stdio:${DISC} is written, verified and ejected."* ]]
  image_on_disc
}

@test "the Write tab writes nothing when the typed name is wrong" {
  # Arrange
  linux_only
  blank_dvd
  answers "${IMAGE}" sr0

  # Act
  run on_terminal '1\nwq' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Nothing was written."* ]]
  [[ ! -s "${DISC}" ]]
}

@test "the Write tab shows why a burn failed" {
  # Arrange
  linux_only
  blank_dvd
  disk_test_drive_flag fail_write
  answers "${IMAGE}" disc.iso

  # Act
  run on_terminal_in_steps '1\nw' 'the result says why' 'xq' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"The write failed; the result says why."* ]]
  [[ "${shown}" == *"enban: the write to"*"Job could not be performed"* ]]
}

@test "the Write tab keeps the app open while a write runs and cancels it on c" {
  # Arrange
  linux_only
  blank_dvd
  disk_test_drive_flag slow
  answers "${IMAGE}" disc.iso

  # Act
  run on_terminal_in_steps '1\nw' 'Press c to cancel' 'xqcq' --drive "stdio:${DISC}"

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"A write is running. Press c to cancel it first."* ]]
  [[ "${final}" == *"Cancelled while writing. The disc may be unusable."* ]]
}

@test "Enter on a result brings the form back" {
  # Arrange
  linux_only
  blank_dvd
  answers "${IMAGE}" disc.iso

  # Act
  run on_terminal_in_steps '1\nw' 'is written, verified and ejected' '\nq' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Image      ${IMAGE}"* ]]
}

@test "the Write tab asks for an image before it writes" {
  # Arrange
  local keys='1wq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Choose an image first: Enter on Image."* ]]
}

@test "the Write tab needs a drive to write to" {
  # Arrange
  answers "${IMAGE}"

  # Act
  run on_terminal '1\nwq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to write to."* ]]
}

@test "the Write tab names an image that does not exist" {
  # Arrange
  answers "${WORK}/missing.iso"

  # Act
  run on_terminal '1\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"No image at ${WORK}/missing.iso."* ]]
}

@test "the Write tab refuses a file that is not whole sectors" {
  # Arrange
  printf 'x' >>"${IMAGE}"
  answers "${IMAGE}"

  # Act
  run on_terminal '1\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"is not a disc image: its size is not whole 2048-byte sectors."* ]]
}

@test "the Write tab keeps the image when the prompt is left empty" {
  # Arrange
  answers ""

  # Act
  run on_terminal '1\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Image      none chosen, press Enter"* ]]
}

@test "the Write tab takes a speed and refuses one that is not a number" {
  # Arrange
  answers 8 fast

  # Act
  run on_terminal '1\033[B\n\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Speed      8"* ]]
  [[ "${shown}" == *"The speed must be a whole number, such as 8."* ]]
}

@test "space and Enter turn verify and eject off" {
  # Arrange
  local keys='1\033[B\033[B \033[B\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"  Verify     [ ] off"* ]]
  [[ "${shown}" == *"> Eject      [ ] off"* ]]
}

@test "the fields stop at the top and the bottom of the form" {
  # Arrange
  local keys='1\033[A\033[B\033[B\033[B\033[B\033[B\033[B \033[A \nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"  Verify     [x] on"* ]]
  [[ "${shown}" == *"> Eject      [x] on"* ]]
  [[ "${shown}" == *"  Test mode  [x] on"* ]]
}

@test "space on a field with nothing to turn leaves it alone" {
  # Arrange
  local keys='1 q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Image      none chosen, press Enter"* ]]
}

@test "the Write tab asks on a plain line when gum is missing" {
  # Arrange
  APP_PATH="$(disk_test_farm gum)"
  export APP_PATH

  # Act
  run on_terminal "1\n${WORK}/missing.iso\nq"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"No image at ${WORK}/missing.iso."* ]]
}

@test "the Write tab starts nothing while a read runs" {
  # Arrange
  local call='DISK_APP_JOB=running DISK_APP_JOB_KIND=read DISK_APP_JOB_PID=1 DISK_APP_W_IMAGE=image.iso; disk_write_tab_start; printf "%s|%s|%s\n" "${DISK_APP_JOB_KIND}" "${DISK_APP_JOB_PID}" "${DISK_APP_STATUS}"'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "read|1|A read is running. Press c on its tab to cancel it first." ]]
}

@test "Enter on Copies sets how many copies to write" {
  # Arrange
  answers 3
  local keys
  keys="1$(printf '\\033[B%.0s' {1..5})\\nq"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Copies     3"* ]]
}

@test "the Copies field refuses a count out of range" {
  # Arrange
  answers 0
  local keys
  keys="1$(printf '\\033[B%.0s' {1..5})\\nq"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Copies     1"* ]]
  [[ "${shown}" == *"The copies must be a whole number from 1 to 100."* ]]
}

@test "space turns Delete on" {
  # Arrange
  local keys
  keys="1$(printf '\\033[B%.0s' {1..6}) q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Delete     [x] the image, after the last copy"* ]]
}
