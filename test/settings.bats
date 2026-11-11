#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-set.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_QUEUE_WAIT
  export ENBAN_CONFIG="${WORK}/config"
  mkdir -p "${ENBAN_CONFIG}"
  SRC="${WORK}/folder"
  OUT="${WORK}/out.iso"
  IMAGE="${WORK}/image.iso"
  DISC="${WORK}/disc.iso"
  DRIVE="stdio:${DISC}"
  mkdir -p "${SRC}"
  head -c 3000 /dev/urandom >"${SRC}/a.txt"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=40 2>/dev/null
  : >"${DISC}"
}

teardown() {
  rm -rf "${WORK}"
}

settings() {
  printf '%s\n' "$@" >"${ENBAN_CONFIG}/settings"
}

kinds() {
  local head
  dd if="$1" of="${WORK}/head.bin" bs=2048 skip=16 count=16 2>/dev/null
  head="$(LC_ALL=C tr -c '%/@CENSR0-9' ' ' <"${WORK}/head.bin")"
  [[ "${head}" != *"%/"[@CE]* ]] || printf 'joliet '
  [[ "${head}" != *NSR0[23]* ]] || printf 'udf '
}

@test "the settings file sets the file systems build writes" {
  # Arrange
  settings "# my defaults" "" "build_fs=iso9660"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" </dev/null

  # Assert
  local found
  found="$(kinds "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${found}" == "" ]]
  [[ "${output}" == *"File systems  ISO9660"* ]]
}

@test "an option wins over the settings file" {
  # Arrange
  settings "build_fs=iso9660"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --fs iso9660,joliet </dev/null

  # Assert
  local found
  found="$(kinds "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${found}" == "joliet " ]]
}

@test "the settings file sets the theme unless the environment names one" {
  # Arrange
  settings "theme=sepia"

  # Act
  run disk_test_run enban version </dev/null

  # Assert
  local themed
  themed="$(ENBAN_THEME=nord disk_test_run enban version </dev/null 2>&1)"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"--theme must be one of"*"got: sepia"* ]]
  [[ "${themed}" == "enban "* ]]
}

@test "a broken line in the settings file warns and the rest still applies" {
  # Arrange
  settings "colour=pink" "queue_wait=soon" "write_speed=fast" "write_verify=maybe" "build_fs=hfs" "build_fs=iso9660"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"enban: warning: settings line 1: unknown setting colour."* ]]
  [[ "${output}" == *"enban: warning: settings line 2: queue_wait must be a whole number of seconds, got: soon"* ]]
  [[ "${output}" == *"enban: warning: settings line 3: write_speed must be auto or a whole number, got: fast"* ]]
  [[ "${output}" == *"enban: warning: settings line 4: write_verify must be yes or no, got: maybe"* ]]
  [[ "${output}" == *"enban: warning: settings line 5: build_fs takes iso9660, joliet and udf with iso9660 among them, got: hfs"* ]]
  [[ "${output}" == *"File systems  ISO9660"* ]]
}

@test "the environment wins over the settings file for the queue wait" {
  # Arrange
  settings "queue_wait=soon" "write_speed=8" "write_speed=auto"
  printf '%s\t%s\n' "${IMAGE}" "${DRIVE}" >"${WORK}/jobs.queue"

  # Act
  ENBAN_QUEUE_WAIT=later run disk_test_run enban queue "${WORK}/jobs.queue" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ENBAN_QUEUE_WAIT must be a whole number of seconds, got: later" ]]
}

@test "the settings file sets how long the queue waits" {
  # Arrange
  settings "queue_wait=1"
  printf '%s\t%s\n' "${IMAGE}" "${DRIVE}" >"${WORK}/jobs.queue"
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  local search_path
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="${DRIVE}" -dao "${IMAGE}" >/dev/null 2>&1

  # Act
  run disk_test_run enban queue "${WORK}/jobs.queue" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"no blank disc in 1 seconds"* ]]
}

@test "the settings file turns the verify and the eject of write off" {
  # Arrange
  settings "write_verify=no" "write_eject=no"
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is written." ]]
}

@test "--verify and --eject turn back on what the settings file turned off" {
  # Arrange
  settings "write_verify=no" "write_eject=no"
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" --verify --eject <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is written, verified and ejected." ]]
}

@test "the settings file turns the verify of read off on its own" {
  # Arrange
  settings "read_verify=no" "write_verify=yes" "write_eject=yes"
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  local search_path
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="${DRIVE}" -dao "${IMAGE}" >/dev/null 2>&1

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/copy.iso" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is read into ${WORK}/copy.iso." ]]
}

@test "write refuses --verify together with --no-verify" {
  # Arrange
  local first=--verify

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" "${first}" --no-verify </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: options '--verify' and '--no-verify' cannot be used together. run 'enban help' for usage." ]]
}
