#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-queue.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_QUEUE_WAIT
  ONE="${WORK}/one.iso"
  TWO="${WORK}/two.iso"
  DISC="${WORK}/disc.iso"
  OTHER="${WORK}/other.iso"
  QUEUE="${WORK}/jobs.queue"
  dd if=/dev/urandom of="${ONE}" bs=2048 count=40 2>/dev/null
  dd if=/dev/urandom of="${TWO}" bs=2048 count=50 2>/dev/null
  : >"${DISC}"
  : >"${OTHER}"
}

teardown() {
  rm -rf "${WORK}"
}

swapping_drive() {
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  disk_test_drive_flag swap
}

burned() {
  local sectors
  sectors=$(($(wc -c <"$1") / 2048))
  cmp -s -n $((sectors * 2048)) "$1" "$2"
}

@test "the queue writes two images in order, one blank disc each" {
  # Arrange
  swapping_drive
  printf '%s\t%s\n' "${ONE}" "stdio:${DISC}" "${TWO}" "stdio:${DISC}" >"${QUEUE}"

  # Act
  run disk_test_run enban queue "${QUEUE}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"1  one.iso"*"stdio:${DISC}"*"1"*"done"* ]]
  [[ "${output}" == *"2  two.iso"*"done"* ]]
  [[ "${output}" == *"Done. 2 images written to 1 drive." ]]
  burned "${ONE}" "${DISC}.1"
  burned "${TWO}" "${DISC}.2"
}

@test "the queue writes each copy on its own disc" {
  # Arrange
  swapping_drive
  printf '%s stdio:%s 8 2\n' "${ONE}" "${DISC}" >"${QUEUE}"

  # Act
  run disk_test_run enban queue "${QUEUE}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 0 ]]
  burned "${ONE}" "${DISC}.1"
  burned "${ONE}" "${DISC}.2"
  [[ "${output}" == *"1  one.iso"*"8x"*"2"*"done"* ]]
}

@test "the queue writes to two drives at once" {
  # Arrange
  swapping_drive
  printf '%s\t%s\n' "${ONE}" "stdio:${DISC}" "${TWO}" "stdio:${OTHER}" >"${QUEUE}"

  # Act
  run disk_test_run enban queue "${QUEUE}" <<<"$(printf '%s\n' disc.iso other.iso)"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. 2 images written to 2 drives." ]]
  burned "${ONE}" "${DISC}.1"
  burned "${TWO}" "${OTHER}.1"
}

@test "the queue gives up on a row when no blank disc arrives in time" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  printf '%s\t%s\n' "${ONE}" "stdio:${DISC}" "${TWO}" "stdio:${DISC}" >"${QUEUE}"

  # Act
  ENBAN_QUEUE_WAIT=2 run disk_test_run enban queue "${QUEUE}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"1  one.iso"*"done"* ]]
  [[ "${output}" == *"2  two.iso"*"no blank disc in 2 seconds"* ]]
  [[ "${output}" == *"enban: 1 of 2 images failed; the table says why." ]]
  burned "${ONE}" "${DISC}"
}

@test "the queue keeps going after a row that fails" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 45 22160
  disk_test_drive_flag swap
  printf '%s\t%s\n' "${TWO}" "stdio:${DISC}" "${ONE}" "stdio:${DISC}" >"${QUEUE}"

  # Act
  run disk_test_run enban queue "${QUEUE}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"1  two.iso"*"needs 50 sectors"* ]]
  [[ "${output}" == *"2  one.iso"*"done"* ]]
}

@test "the queue writes nothing without each drive's name" {
  # Arrange
  swapping_drive
  printf '%s\t%s\n' "${ONE}" "stdio:${DISC}" >"${QUEUE}"

  # Act
  run disk_test_run enban queue "${QUEUE}" <<<"wrong"

  # Assert
  local size
  size="$(wc -c <"${DISC}")"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: cancelled, nothing was written." ]]
  [[ "${size//[[:space:]]/}" -eq 0 ]]
}

@test "the queue names the line of an image that is missing" {
  # Arrange
  printf '\n# family discs\n%s\t%s\n%s\t%s\n' "${ONE}" "stdio:${DISC}" "${WORK}/gone.iso" "stdio:${DISC}" >"${QUEUE}"

  # Act
  run disk_test_run enban queue "${QUEUE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: queue line 4: no image at ${WORK}/gone.iso." ]]
}

@test "the queue names a line without a drive" {
  # Arrange
  printf '%s\n' "${ONE}" >"${QUEUE}"

  # Act
  run disk_test_run enban queue "${QUEUE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: queue line 1: name a drive after the image." ]]
}

@test "the queue refuses a speed that is not a number" {
  # Arrange
  printf '%s\t%s\tfast\n' "${ONE}" "stdio:${DISC}" >"${QUEUE}"

  # Act
  run disk_test_run enban queue "${QUEUE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: queue line 1: the speed must be auto or a whole number, got: fast" ]]
}

@test "the queue refuses a copy count below one" {
  # Arrange
  printf '%s\t%s\tauto\t0\n' "${ONE}" "stdio:${DISC}" >"${QUEUE}"

  # Act
  run disk_test_run enban queue "${QUEUE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: queue line 1: the copies must be a whole number from 1, got: 0" ]]
}

@test "the queue refuses an empty queue file" {
  # Arrange
  printf '# nothing yet\n' >"${QUEUE}"

  # Act
  run disk_test_run enban queue "${QUEUE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${QUEUE} holds no images to write." ]]
}

@test "the queue says when the queue file is missing" {
  # Arrange
  local queue="${WORK}/none.queue"

  # Act
  run disk_test_run enban queue "${queue}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no queue file at ${queue}." ]]
}

@test "the queue refuses a wait that is not a number" {
  # Arrange
  printf '%s\t%s\n' "${ONE}" "stdio:${DISC}" >"${QUEUE}"

  # Act
  ENBAN_QUEUE_WAIT=soon run disk_test_run enban queue "${QUEUE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ENBAN_QUEUE_WAIT must be a whole number of seconds, got: soon" ]]
}

@test "the queue draws its result with gum" {
  # Arrange
  swapping_drive
  printf '%s\t%s\n' "${ONE}" "stdio:${DISC}" >"${QUEUE}"
  export ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log"

  # Act
  run disk_test_run enban queue "${QUEUE}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 0 ]]
  grep -qF -- "Done. 1 image written to 1 drive." "${WORK}/gum.log"
}

@test "enban queue without a file stops with the usage hint" {
  # Arrange
  local command=queue

  # Act
  run disk_test_run enban "${command}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: queue needs a queue file. run 'enban help' for usage." ]]
}

@test "the queue names a line whose file is not a disc image" {
  # Arrange
  printf 'odd' >>"${ONE}"
  printf '%s\t%s\n' "${ONE}" "stdio:${DISC}" >"${QUEUE}"

  # Act
  run disk_test_run enban queue "${QUEUE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: queue line 1: ${ONE} is not a disc image: its size is not a whole number of 2048-byte sectors." ]]
}
