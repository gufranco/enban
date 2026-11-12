#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-qtab.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_TEST_GUM APP_PATH ENBAN_QUEUE_WAIT
  ONE="${WORK}/one.iso"
  TWO="${WORK}/two.iso"
  DISC="${WORK}/disc.iso"
  dd if=/dev/urandom of="${ONE}" bs=2048 count=40 2>/dev/null
  dd if=/dev/urandom of="${TWO}" bs=2048 count=50 2>/dev/null
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

@test "a adds an image and asks for its drive when none is chosen" {
  # Arrange
  answers "${ONE}" /dev/sr1

  # Act
  run on_terminal '6aq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> 1  one.iso"*"/dev/sr1"*"auto"*"1"*"waiting"* ]]
  [[ "${shown}" == *"Images       1 on 1 drive"* ]]
}

@test "a refuses a file that is not a disc image" {
  # Arrange
  printf 'odd' >>"${ONE}"
  answers "${ONE}"

  # Act
  run on_terminal '6aq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"is not a disc image: its size is not whole 2048-byte sectors."* ]]
  [[ "${shown}" == *"Nothing queued yet. Press a to add an image."* ]]
}

@test "a keeps the queue as it was when no drive is named" {
  # Arrange
  answers "${ONE}" ""

  # Act
  run on_terminal '6aq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Nothing queued yet. Press a to add an image."* ]]
}

@test "J and K move the focused image down and up the queue" {
  # Arrange
  answers "${ONE}" /dev/sr1 "${TWO}" /dev/sr1

  # Act
  run on_terminal_in_steps '6aa\033[AJ' '2  one.iso' 'Kq'

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"1  two.iso"*"> 2  one.iso"* ]]
  [[ "${final}" == *"> 1  one.iso"*"2  two.iso"* ]]
}

@test "x removes the focused image" {
  # Arrange
  answers "${ONE}" /dev/sr1 "${TWO}" /dev/sr1

  # Act
  run on_terminal '6aaxq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> 1  one.iso"* ]]
  [[ "${shown}" != *"2  two.iso"* ]]
  [[ "${shown}" == *"Removed two.iso."* ]]
}

@test "Enter sets the speed and the copies of the focused image" {
  # Arrange
  answers "${ONE}" /dev/sr1 8 3

  # Act
  run on_terminal '6a\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> 1  one.iso"*"8x"*"3"* ]]
}

@test "space marks images and Enter sets the speed and copies of every marked one" {
  # Arrange
  answers "${ONE}" /dev/sr1 "${TWO}" /dev/sr1 8 3

  # Act
  run on_terminal '6aa \033[A \nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *">*1  one.iso"*"8x"*"3"* ]]
  [[ "${shown}" == *" *2  two.iso"*"8x"*"3"* ]]
  [[ "${shown}" == *"Set 2 images to speed 8, 3 copies."* ]]
}

@test "space on a marked image unmarks it" {
  # Arrange
  answers "${ONE}" /dev/sr1

  # Act
  run on_terminal '6a  q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> 1  one.iso"* ]]
}

@test "d deletes each image once it is written" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  disk_test_drive_flag swap
  answers "${ONE}" "${TWO}" disc.iso

  # Act
  run on_terminal_in_steps '6aads' 'images written to' 'q' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"1  one.iso"*"done, image deleted"* ]]
  [[ ! -e "${ONE}" ]]
  [[ ! -e "${TWO}" ]]
}

@test "p pauses a running queue and p again lets it go on" {
  # Arrange
  mkdir -p "${WORK}/job/queue"
  local call
  call="DISK_APP_JOB_DIR='${WORK}/job' DISK_APP_JOB=running DISK_APP_JOB_KIND=queue; disk_queue_tab_key p; printf '%s|' \"\${DISK_APP_STATUS}\"; [ -e '${WORK}/job/queue/paused' ] && printf 'held|'; disk_queue_tab_key p; printf '%s|' \"\${DISK_APP_STATUS}\"; [ -e '${WORK}/job/queue/paused' ] || printf 'free'"

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "The queue pauses before its next image. Press p to go on.|held|The queue goes on with the next image.|free" ]]
}

@test "Enter keeps the row when the speed or copies are not numbers" {
  # Arrange
  answers "${ONE}" /dev/sr1 fast "${ONE}" /dev/sr1 auto 0

  # Act
  run on_terminal_in_steps '6a\n' 'The speed must be' 'a\nq'

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"The speed must be auto or a whole number, such as 8."* ]]
  [[ "${final}" == *"The copies must be a whole number from 1."* ]]
}

@test "o saves the queue as a file queue reads" {
  # Arrange
  answers "${ONE}" /dev/sr1 "${WORK}/saved.queue"

  # Act
  run on_terminal '6aoq'

  # Assert
  local shown saved
  shown="$(last_frame)"
  saved="$(cat "${WORK}/saved.queue")"
  [[ "${shown}" == *"Saved the queue to ${WORK}/saved.queue."* ]]
  [[ "${saved}" == "${ONE}"$'\t'"/dev/sr1"$'\t'"auto"$'\t'"1" ]]
}

@test "o never overwrites a file" {
  # Arrange
  printf 'keep\n' >"${WORK}/saved.queue"
  answers "${ONE}" /dev/sr1 "${WORK}/saved.queue"

  # Act
  run on_terminal '6aoq'

  # Assert
  local shown kept
  shown="$(last_frame)"
  kept="$(cat "${WORK}/saved.queue")"
  [[ "${shown}" == *"${WORK}/saved.queue already exists. Choose a new name."* ]]
  [[ "${kept}" == "keep" ]]
}

@test "s and o need an image in the queue" {
  # Arrange
  local keys='6s'

  # Act
  run on_terminal_in_steps "${keys}" 'Add an image first' 'oq'

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"Add an image first: press a."* ]]
  [[ "${final}" == *"Add an image first: press a."* ]]
}

@test "s writes nothing without each drive's name" {
  # Arrange
  answers "${ONE}" /dev/sr1 wrong

  # Act
  run on_terminal '6asq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Nothing was written."* ]]
}

@test "s writes the queue and shows each image done" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  disk_test_drive_flag swap
  answers "${ONE}" "${TWO}" disc.iso

  # Act
  run on_terminal_in_steps '6aas' 'images written to' 'q' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Result"*"1  one.iso"*"done"*"2  two.iso"*"done"* ]]
  [[ "${shown}" == *"Done. 2 images written to 1 drive."* ]]
}

@test "the queue table shows each image's state while it runs" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  disk_test_drive_flag slow
  answers "${ONE}" disc.iso y

  # Act
  run on_terminal_in_steps '6as' 'writing' 'pcq' --drive "stdio:${DISC}"

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"1  one.iso"*"writing"* ]]
  [[ "${shown}" == *"The queue pauses before its next image. Press p to go on."* ]]
  [[ "${final}" == *"Cancelled while writing the queue. A disc in a drive may be unusable."* ]]
}

@test "the Queue tab starts nothing while a read runs" {
  # Arrange
  local call='DISK_APP_JOB=running DISK_APP_JOB_KIND=read DISK_APP_JOB_PID=1 DISK_APP_Q_ROWS="$(printf "a\tb\tauto\t1")"; disk_queue_tab_start; printf "%s|%s|%s\n" "${DISK_APP_JOB_KIND}" "${DISK_APP_JOB_PID}" "${DISK_APP_STATUS}"'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "read|1|A read is running. Press c on its tab to cancel it first." ]]
}

@test "the Queue tab ignores other keys" {
  # Arrange
  local keys='6zq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Write queue"* ]]
}
