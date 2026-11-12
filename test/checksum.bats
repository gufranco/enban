#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-sum.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  IMAGE="${WORK}/image.iso"
  DISC="${WORK}/disc.iso"
  DRIVE="stdio:${DISC}"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=96 2>/dev/null
  : >"${DISC}"
}

teardown() {
  rm -rf "${WORK}"
}

digest() {
  local line
  line="$(openssl dgst "-$1" "$2")"
  printf '%s\n' "${line##* }"
}

@test "enban checksum prints the MD5, SHA-1 and SHA-256 of an image" {
  # Arrange
  local md5 sha1 sha256
  md5="$(digest md5 "${IMAGE}")"
  sha1="$(digest sha1 "${IMAGE}")"
  sha256="$(digest sha256 "${IMAGE}")"

  # Act
  run disk_test_run enban checksum "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "MD5      ${md5}" ]]
  [[ "${lines[1]}" == "SHA-1    ${sha1}" ]]
  [[ "${lines[2]}" == "SHA-256  ${sha256}" ]]
  [[ "${lines[3]}" == "Done. ${IMAGE} is checked." ]]
}

@test "enban checksum reads the readable sectors of the disc in the drive" {
  # Arrange
  local search_path sha256
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="${DRIVE}" -dao "${IMAGE}" >/dev/null 2>&1
  sha256="$(digest sha256 "${DISC}")"

  # Act
  run disk_test_run enban checksum --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[2]}" == "SHA-256  ${sha256}" ]]
  [[ "${lines[3]}" == "Done. the disc in ${DRIVE} is checked." ]]
}

@test "enban checksum refuses a blank disc" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160

  # Act
  run disk_test_run enban checksum --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: the disc in ${DRIVE} holds no data to check." ]]
}

@test "enban checksum says when the disc cannot be read" {
  # Arrange
  local search_path
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="${DRIVE}" -dao "${IMAGE}" >/dev/null 2>&1
  disk_test_shim dd "case \" \$* \" in *\" if=\"*) exit 1 ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"

  # Act
  run disk_test_run enban checksum --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to read the disc in ${DRIVE}." ]]
}

@test "enban checksum stops on macOS when asked for a disc" {
  # Arrange
  local drive=/dev/disk4

  # Act
  ENBAN_OS=Darwin run disk_test_run enban checksum --drive "${drive}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: on macOS name a drive like IODVDServices/0 or IOCompactDiscServices/0, or an image like stdio:disc.iso, so checksum cannot use ${drive}." ]]
}

@test "enban checksum says when there is no image" {
  # Arrange
  local image="${WORK}/missing.iso"

  # Act
  run disk_test_run enban checksum "${image}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no image at ${image}." ]]
}

@test "enban checksum draws its result with gum" {
  # Arrange
  export ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log"

  # Act
  run disk_test_run enban checksum "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  grep -qF -- "Done. ${IMAGE} is checked." "${WORK}/gum.log"
}

@test "enban checksum needs an image or a drive" {
  # Arrange
  local command=checksum

  # Act
  run disk_test_run enban "${command}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: checksum needs an image or --drive. run 'enban help' for usage." ]]
}

@test "enban checksum takes an image or a drive, not both" {
  # Arrange
  local image="${IMAGE}"

  # Act
  run disk_test_run enban checksum "${image}" --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: checksum takes an image or --drive, not both. run 'enban help' for usage." ]]
}
