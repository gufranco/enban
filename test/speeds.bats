#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-speeds.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  export ENBAN_DATA="${WORK}/data"
  DISC="${WORK}/disc.iso"
  DRIVE="stdio:${DISC}"
  IMAGE="${WORK}/image.iso"
  : >"${DISC}"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=64 2>/dev/null
}

teardown() {
  rm -rf "${WORK}"
}

linux_only() {
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
}

blank_dvd() {
  : >"${DISC}"
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  printf 'product=MCC 03RG20\n' >>"${WORK}/drive.state"
}

burn_speed() {
  sed -n 's/^burn=.* speed=\([0-9]*\) .*/\1/p' "${WORK}/drive.state"
}

@test "enban write remembers the speed it wrote a disc ID at" {
  # Arrange
  linux_only
  blank_dvd

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" --speed 8 --no-verify --no-eject <<<"disc.iso"

  # Assert
  local kept
  kept="$(cat "${ENBAN_DATA}/speeds.tsv")"
  [[ "${status}" -eq 0 ]]
  [[ "${kept}" == "$(printf 'YOYODYNE WARP DRIVE\tMCC 03RG20\t8')" ]]
}

@test "enban write uses the remembered speed when none is given" {
  # Arrange
  linux_only
  blank_dvd
  mkdir -p "${ENBAN_DATA}"
  printf 'YOYODYNE WARP DRIVE\tMCC 03RG20\t4\n' >"${ENBAN_DATA}/speeds.tsv"

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" --no-verify --no-eject <<<"disc.iso"

  # Assert
  local speed
  speed="$(burn_speed)"
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "Writing at 4x, the speed remembered for MCC 03RG20 in this drive." ]]
  [[ "${speed}" == "4" ]]
}

@test "enban write keeps one speed per disc ID and drive" {
  # Arrange
  linux_only
  blank_dvd
  mkdir -p "${ENBAN_DATA}"
  printf 'YOYODYNE WARP DRIVE\tMCC 03RG20\t4\nother drive\tMCC 03RG20\t2\n' >"${ENBAN_DATA}/speeds.tsv"

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" --speed 16 --no-verify --no-eject <<<"disc.iso"

  # Assert
  local kept
  kept="$(LC_ALL=C sort "${ENBAN_DATA}/speeds.tsv")"
  [[ "${status}" -eq 0 ]]
  [[ "${kept}" == "$(printf 'YOYODYNE WARP DRIVE\tMCC 03RG20\t16\nother drive\tMCC 03RG20\t2')" ]]
}

@test "enban write says when the speed cannot be remembered" {
  # Arrange
  linux_only
  blank_dvd
  printf 'not a folder' >"${ENBAN_DATA}"

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" --speed 8 --no-verify --no-eject <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"enban: warning: the disc is written, but its speed is not remembered: ${ENBAN_DATA} is not writable."* ]]
}

@test "enban write keeps every speed when ten writes end at once" {
  # Arrange
  linux_only
  local count=0
  blank_dvd
  sed -i 's/^product=.*/product=file/' "${WORK}/drive.state"
  while [[ "${count}" -lt 10 ]]; do
    : >"${WORK}/disc${count}.iso"
    count=$((count + 1))
  done

  # Act
  local index
  for index in 0 1 2 3 4 5 6 7 8 9; do
    disk_test_run enban write "${IMAGE}" --drive "stdio:${WORK}/disc${index}.iso" --speed 8 --no-verify --no-eject <<<"disc${index}.iso" >"${WORK}/out${index}" 2>&1 &
  done
  wait

  # Assert
  local kept
  cut -f 2 "${ENBAN_DATA}/speeds.tsv" >"${WORK}/ids"
  kept="$(LC_ALL=C sort "${WORK}/ids")"
  [[ "${kept}" == "$(printf 'disc%s.iso\n' 0 1 2 3 4 5 6 7 8 9)" ]]
}

@test "enban write leaves the speeds alone while another enban holds them" {
  # Arrange
  linux_only
  blank_dvd
  mkdir -p "${ENBAN_DATA}"
  : >"${ENBAN_DATA}/.speeds.lock"

  # Act
  run disk_test_run enban write "${IMAGE}" --drive "${DRIVE}" --speed 8 --no-verify --no-eject <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"enban: warning: the disc is written, but its speed is not remembered: ${ENBAN_DATA}/.speeds.lock stayed taken."* ]]
  [[ ! -e "${ENBAN_DATA}/speeds.tsv" ]]
}

@test "enban speeds lists each remembered speed" {
  # Arrange
  mkdir -p "${ENBAN_DATA}"
  printf 'ASUS SDRW-08U9M-U\tMCC 03RG20\t8\nASUS SDRW-08U9M-U\tCMC MAG AE1\t16\n' >"${ENBAN_DATA}/speeds.tsv"

  # Act
  run disk_test_run enban speeds </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "ASUS SDRW-08U9M-U           CMC MAG AE1     16x" ]]
  [[ "${lines[1]}" == "ASUS SDRW-08U9M-U           MCC 03RG20      8x" ]]
}

@test "enban speeds draws its table with gum" {
  # Arrange
  mkdir -p "${ENBAN_DATA}"
  printf 'ASUS SDRW-08U9M-U\tMCC 03RG20\t8\n' >"${ENBAN_DATA}/speeds.tsv"
  export ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log"

  # Act
  run disk_test_run enban speeds </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  grep -qF 'MCC 03RG20' "${WORK}/gum.log"
}

@test "enban speeds says when nothing is remembered" {
  # Arrange
  local command=speeds

  # Act
  run disk_test_run enban "${command}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "No speeds remembered yet. a write with --speed remembers its speed for that disc ID and drive." ]]
}
