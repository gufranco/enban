#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-read.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  IMAGE="${WORK}/image.iso"
  DISC="${WORK}/disc.iso"
  DRIVE="stdio:${DISC}"
  OUT="${WORK}/copy.iso"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=512 2>/dev/null
  : >"${DISC}"
}

teardown() {
  rm -rf "${WORK}"
}

linux_only() {
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
}

written_dvd() {
  local search_path
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="${DRIVE}" -dao "${IMAGE}" >/dev/null 2>&1
}

prefix_of() {
  local size
  size="$(wc -c <"$1")"
  cmp -s -n "${size}" "$1" "$2"
}

@test "enban read copies the disc to an image and prints its SHA-256" {
  # Arrange
  linux_only
  written_dvd

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  prefix_of "${IMAGE}" "${OUT}"
  prefix_of "${OUT}" "${DISC}"
  local digest
  digest="$(sha256sum "${OUT}")"
  [[ "${output}" == *"SHA-256  ${digest%% *}"* ]]
  [[ "${output}" == *"Done. ${DRIVE} is read into ${OUT} and verified." ]]
}

@test "enban read skips the second read with --no-verify" {
  # Arrange
  linux_only
  written_dvd

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" --no-verify </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is read into ${OUT}." ]]
}

@test "enban read refuses a disc with no data" {
  # Arrange
  linux_only
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: the disc in ${DRIVE} holds no data to read." ]]
  [[ ! -e "${OUT}" ]]
}

@test "enban read never overwrites a file" {
  # Arrange
  linux_only
  written_dvd
  printf 'keep\n' >"${OUT}"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${OUT} already exists." ]]
  local kept
  kept="$(cat "${OUT}")"
  [[ "${kept}" == "keep" ]]
}

@test "enban read says when it cannot write the image" {
  # Arrange
  linux_only
  written_dvd
  local out="${WORK}/missing/copy.iso"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${out}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to read ${DRIVE} into ${out}." ]]
}

@test "enban read reports a copy that does not match the disc" {
  # Arrange
  linux_only
  written_dvd
  disk_test_shim dd "case \" \$* \" in *\" of=\"*) \"\${REAL}\" \"\$@\" && printf X | \"\${REAL}\" of='${OUT}' bs=1 seek=100 conv=notrunc 2>/dev/null ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the copy in ${OUT} does not match the disc in ${DRIVE}." ]]
}

@test "enban read draws its result with gum" {
  # Arrange
  linux_only
  written_dvd
  export ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  grep -qF -- "Done. ${DRIVE} is read into ${OUT} and verified." "${WORK}/gum.log"
}

@test "enban read stops on macOS, where reading a drive is not supported yet" {
  # Arrange
  local drive=/dev/disk4

  # Act
  ENBAN_OS=Darwin run disk_test_run enban read --drive "${drive}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: reading a drive is not supported on macOS yet, so read stops here." ]]
}

@test "enban read without an image name stops with the usage hint" {
  # Arrange
  local option=--drive

  # Act
  run disk_test_run enban read "${option}" "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: read needs a file to write the image to. run 'enban help' for usage." ]]
}

@test "enban read without --drive stops with the usage hint" {
  # Arrange
  local out="${OUT}"

  # Act
  run disk_test_run enban read "${out}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: read needs --drive. run 'enban help' for usage." ]]
}

@test "enban read refuses an option that only write takes" {
  # Arrange
  local option=--speed

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" "${option}" 8 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--speed' works only with write and discovery. run 'enban help' for usage." ]]
}
