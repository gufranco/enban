#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-vtab.XXXXXX")"
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

answers() {
  printf '%s\n' "$@" >"${ENBAN_TEST_GUM_ANSWERS}"
}

written_dvd() {
  local search_path
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="stdio:${DISC}" -dao "${IMAGE}" >/dev/null 2>&1
}

@test "the Verify tab compares the disc with the chosen image and shows the result" {
  # Arrange
  written_dvd
  answers "${IMAGE}"

  # Act
  run on_terminal_in_steps '4\033[B\nv' 'byte for byte' 'q' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"Result"*"Readable     64 of 64 sectors"*"Miscompares  0"* ]]
}

@test "the Verify tab names the first sector that differs" {
  # Arrange
  written_dvd
  printf 'XX' | dd of="${DISC}" bs=1 seek=$((20 * 2048)) conv=notrunc 2>/dev/null
  answers "${IMAGE}"

  # Act
  run on_terminal_in_steps '4\033[B\nv' 'the result says why' 'q' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"first at sector 20."* ]]
}

@test "the Verify tab checks every sector when the image comparison is off" {
  # Arrange
  written_dvd

  # Act
  run on_terminal_in_steps '4 v' 'can be read' 'q' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Done. every sector of stdio:${DISC} can be read."* ]]
}

@test "the Verify tab cancels a verify on c" {
  # Arrange
  written_dvd
  answers y
  disk_test_shim dd "case \" \$* \" in *\" if=\"*) sleep 37 ;; esac; exec \"\${REAL}\" \"\$@\""

  # Act
  run on_terminal_in_steps '4 v' 'Press c to cancel' 'cq' --drive "stdio:${DISC}"

  # Assert
  local shown left
  shown="$(last_frame)"
  left="$(pgrep -f 'sleep 37' || true)"
  [[ "${shown}" == *"Cancelled while verifying. Nothing on the disc changed."* ]]
  [[ -z "${left}" ]]
}

@test "the Verify tab asks for an image before it compares" {
  # Arrange
  local keys='4vq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Choose an image first: Enter on Image."* ]]
}

@test "the Verify tab needs a drive to verify" {
  # Arrange
  answers "${IMAGE}"

  # Act
  run on_terminal '4\033[B\nvq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to verify."* ]]
}

@test "the Verify tab refuses an image that does not exist" {
  # Arrange
  answers "${WORK}/missing.iso"

  # Act
  run on_terminal '4\033[B\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"No image at ${WORK}/missing.iso."* ]]
}

@test "the Verify tab shows the chosen image" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '40 200\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  answers "${IMAGE}"

  # Act
  run on_terminal '4\033[B\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Image      ${IMAGE}"* ]]
  [[ "${shown}" == *"Ready to verify 64 sectors. Press v to verify."* ]]
}

@test "space and Enter turn the image comparison off and on" {
  # Arrange
  local keys='4 \033[B \033[A\n\n\033[Bq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"  Compare    [ ] off"* ]]
}

@test "the Verify tab ignores other keys" {
  # Arrange
  local keys='4xq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Verify disc"*"> Compare    [x] on"* ]]
}

@test "the Verify tab starts nothing while a read runs" {
  # Arrange
  local call='DISK_APP_JOB=running DISK_APP_JOB_KIND=read DISK_APP_JOB_PID=1; disk_verify_tab_start; printf "%s|%s|%s\n" "${DISK_APP_JOB_KIND}" "${DISK_APP_JOB_PID}" "${DISK_APP_STATUS}"'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "read|1|A read is running. Press c on its tab to cancel it first." ]]
}
