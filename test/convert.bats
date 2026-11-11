#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-conv.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  OUT="${WORK}/out.iso"
  DATA="${WORK}/data.iso"
  dd if=/dev/urandom of="${DATA}" bs=2048 count=6 2>/dev/null
}

teardown() {
  rm -rf "${WORK}"
}

linux_only() {
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "bchunk and iat are tested on Linux"
}

raw_bin() {
  local sector=0 bytes count
  bytes="$(wc -c <"$1")"
  count=$((bytes / 2048))
  : >"$2"
  while [[ "${sector}" -lt "${count}" ]]; do
    {
      printf '\000\377\377\377\377\377\377\377\377\377\377\000\000\002\000\001'
      dd if="$1" bs=2048 skip="${sector}" count=1 2>/dev/null
      head -c 288 /dev/zero
    } >>"$2"
    sector=$((sector + 1))
  done
}

@test "enban convert turns a BIN/CUE image into an ISO" {
  # Arrange
  linux_only
  raw_bin "${DATA}" "${WORK}/disc.bin"
  printf 'FILE "disc.bin" BINARY\n  TRACK 01 MODE1/2352\n    INDEX 01 00:00:00\n' >"${WORK}/disc.cue"

  # Act
  run disk_test_run enban convert "${WORK}/disc.cue" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  cmp -s "${DATA}" "${OUT}"
  [[ "${output}" == *"Done. ${OUT} is converted from ${WORK}/disc.cue." ]]
}

@test "enban convert turns another image into an ISO through iat" {
  # Arrange
  linux_only
  local search_path
  mkdir -p "${WORK}/files"
  printf 'hello\n' >"${WORK}/files/a.txt"
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as mkisofs -quiet -o "${WORK}/real.iso" "${WORK}/files" 2>/dev/null
  raw_bin "${WORK}/real.iso" "${WORK}/disc.img"

  # Act
  run disk_test_run enban convert "${WORK}/disc.img" "${OUT}" </dev/null

  # Assert
  local volume
  volume="$(dd if="${OUT}" bs=1 skip=32769 count=5 2>/dev/null)"
  [[ "${status}" -eq 0 ]]
  [[ "${volume}" == "CD001" ]]
}

@test "enban convert says when the tool cannot convert the image" {
  # Arrange
  linux_only
  printf 'nothing to see' >"${WORK}/disc.nrg"

  # Act
  run disk_test_run enban convert "${WORK}/disc.nrg" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to convert ${WORK}/disc.nrg into ${OUT}." ]]
  [[ ! -e "${OUT}" ]]
}

@test "enban convert names the tool it needs" {
  # Arrange
  printf 'FILE "disc.bin" BINARY\n' >"${WORK}/disc.cue"
  local farm
  farm="$(disk_test_farm bchunk)"

  # Act
  run disk_test_run_path "${farm}" enban convert "${WORK}/disc.cue" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: convert needs bchunk for a CUE image. install it and try again." ]]
}

@test "enban convert reads the BIN file the CUE names" {
  # Arrange
  printf 'TRACK 01 MODE1/2352\n' >"${WORK}/disc.cue"
  disk_test_shim bchunk "exit 0"

  # Act
  run disk_test_run enban convert "${WORK}/disc.cue" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${WORK}/disc.cue names no BIN file." ]]
}

@test "enban convert never overwrites a file and needs the image" {
  # Arrange
  printf 'keep\n' >"${OUT}"
  cp "${DATA}" "${WORK}/disc.mdf"

  # Act
  run disk_test_run enban convert "${WORK}/disc.mdf" "${OUT}" </dev/null

  # Assert
  local missing
  missing="$(disk_test_run enban convert "${WORK}/none.mdf" "${WORK}/new.iso" </dev/null 2>&1 || true)"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${OUT} already exists." ]]
  [[ "${missing}" == "enban: no image at ${WORK}/none.mdf." ]]
}

@test "enban convert needs an image and an ISO to create" {
  # Arrange
  local image="${WORK}/disc.mdf"

  # Act
  run disk_test_run enban convert "${image}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: convert needs an image and an ISO file to create. run 'enban help' for usage." ]]
}

@test "enban convert says when the image is already an ISO" {
  # Arrange
  linux_only
  local search_path
  mkdir -p "${WORK}/files"
  printf 'hello\n' >"${WORK}/files/a.txt"
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as mkisofs -quiet -o "${WORK}/disc.mdf" "${WORK}/files" 2>/dev/null

  # Act
  run disk_test_run enban convert "${WORK}/disc.mdf" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${WORK}/disc.mdf is already an ISO image, so it needs no conversion." ]]
}

@test "enban convert reads a BIN file named by its full path" {
  # Arrange
  linux_only
  mkdir -p "${WORK}/bins"
  raw_bin "${DATA}" "${WORK}/bins/disc.bin"
  printf 'FILE "%s" BINARY\n  TRACK 01 MODE1/2352\n    INDEX 01 00:00:00\n' "${WORK}/bins/disc.bin" >"${WORK}/disc.cue"

  # Act
  run disk_test_run enban convert "${WORK}/disc.cue" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  cmp -s "${DATA}" "${OUT}"
}
