#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-rtab.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_TEST_GUM APP_PATH
  IMAGE="${WORK}/image.iso"
  DISC="${WORK}/disc.iso"
  OUT="${WORK}/copy.iso"
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

@test "the Read tab copies the disc into the chosen file and shows the result" {
  # Arrange
  written_dvd
  answers "${OUT}"

  # Act
  run on_terminal_in_steps '2\nr' 'and verified' 'q' --drive "stdio:${DISC}"

  # Assert
  local shown bytes
  shown="$(last_frame)"
  bytes="$(wc -c <"${IMAGE}")"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"Result"*"SHA-256"* ]]
  cmp -s -n "${bytes}" "${IMAGE}" "${OUT}"
}

@test "the Read tab shows why a read failed" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  answers "${OUT}"

  # Act
  run on_terminal_in_steps '2\nr' 'the result says why' '\nq' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Image      ${OUT}"* ]]
}

slow_half_read() {
  disk_test_shim dd "case \" \$* \" in *\" of=\"*) head -c 4096 /dev/zero >'${OUT}'; sleep 30 ;; esac; exec \"\${REAL}\" \"\$@\""
}

@test "cancelling a read deletes the half-written image" {
  # Arrange
  written_dvd
  slow_half_read
  answers "${OUT}" y

  # Act
  run on_terminal_in_steps '2\nr' 'Press c to cancel' 'cq' --drive "stdio:${DISC}"

  # Assert
  local final
  final="$(last_frame)"
  [[ "${final}" == *"Cancelled. The half-written files are deleted."* ]]
  [[ ! -e "${OUT}" ]]
}

@test "cancelling a read keeps the half-written image when clean-up is off" {
  # Arrange
  written_dvd
  slow_half_read
  answers "${OUT}" y
  export ENBAN_CONFIG="${WORK}/config"
  mkdir -p "${ENBAN_CONFIG}"
  printf 'event_clean=no\n' >"${ENBAN_CONFIG}/settings"

  # Act
  run on_terminal_in_steps '2\nr' 'Press c to cancel' 'cq' --drive "stdio:${DISC}"

  # Assert
  local final
  final="$(last_frame)"
  [[ "${final}" == *"Cancelled. The half-written ${OUT} is kept."* ]]
  [[ -s "${OUT}" ]]
}

@test "c asks first and any answer but y lets the read go on" {
  # Arrange
  written_dvd
  slow_half_read
  answers "${OUT}" n y

  # Act
  run on_terminal_in_steps '2\nr' 'Press c to cancel' 'ccq' --drive "stdio:${DISC}"

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"The read goes on. Press c to cancel."* ]]
  [[ "${final}" == *"Cancelled while reading. The image is incomplete."* ]]
}

@test "c cancels at once when the cancel question is off" {
  # Arrange
  written_dvd
  slow_half_read
  answers "${OUT}"
  export ENBAN_CONFIG="${WORK}/config"
  mkdir -p "${ENBAN_CONFIG}"
  printf 'event_confirm=no\n' >"${ENBAN_CONFIG}/settings"

  # Act
  run on_terminal_in_steps '2\nr' 'Press c to cancel' 'cq' --drive "stdio:${DISC}"

  # Assert
  local final
  final="$(last_frame)"
  [[ "${final}" == *"Cancelled while reading. The image is incomplete."* ]]
}

@test "the Read tab cancels a read on c" {
  # Arrange
  written_dvd
  disk_test_shim dd "case \" \$* \" in *\" of=\"*) sleep 30 ;; esac; exec \"\${REAL}\" \"\$@\""
  answers "${OUT}" y

  # Act
  run on_terminal_in_steps '2\nr' 'Press c to cancel' 'qcq' --drive "stdio:${DISC}"

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"A read is running. Press c to cancel it first."* ]]
  [[ "${final}" == *"Cancelled while reading. The image is incomplete."* ]]
}

@test "the Read tab asks for a file before it reads" {
  # Arrange
  local keys='2rq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Choose an image file first: Enter on Image."* ]]
}

@test "the Read tab needs a drive to read from" {
  # Arrange
  answers "${OUT}"

  # Act
  run on_terminal '2\nrq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to read from."* ]]
}

@test "the Read tab never picks a file that exists" {
  # Arrange
  answers "${IMAGE}"

  # Act
  run on_terminal '2\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"${IMAGE} already exists. Choose a new name."* ]]
}

@test "the Read tab keeps its file when the prompt is left empty" {
  # Arrange
  answers ""

  # Act
  run on_terminal '2\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Image      none chosen, press Enter"* ]]
}

@test "space and Enter turn the read verify off and on" {
  # Arrange
  local keys='2\033[B \033[A \033[B\n \033[A\033[Bq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Verify     [ ] off"* ]]
}

@test "the Read tab ignores other keys" {
  # Arrange
  local keys='2xq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Read disc to image"* ]]
}

@test "the Read tab starts nothing while a write runs" {
  # Arrange
  local call='DISK_APP_JOB=running DISK_APP_JOB_KIND=write DISK_APP_JOB_PID=1 DISK_APP_R_OUT=new.iso; disk_read_tab_start; printf "%s|%s|%s\n" "${DISK_APP_JOB_KIND}" "${DISK_APP_JOB_PID}" "${DISK_APP_STATUS}"'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "write|1|A write is running. Press c on its tab to cancel it first." ]]
}
