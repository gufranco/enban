#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-audio.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  DISC="${WORK}/disc.iso"
  DRIVE="stdio:${DISC}"
  CUE="${WORK}/album.cue"
  : >"${DISC}"
  printf 'FILE "a.wav" WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n' >"${CUE}"
}

teardown() {
  rm -rf "${WORK}"
}

burner() {
  local name=cdrskin fatal='cdrskin: FATAL : '
  if [[ "${ENBAN_TEST_OS}" != "Linux" ]]; then
    name=cdrecord
    fatal='cdrecord: '
  fi
  disk_test_shim "${name}" "printf '%s\\n' \"\$*\" >>'${WORK}/burner.log'; [ ! -e '${WORK}/burn.fail' ] || { printf '${fatal}Cannot open cue file\\n' >&2; exit 1; }"
}

@test "enban write burns a CUE sheet as an audio CD after the drive's name" {
  # Arrange
  disk_test_drive 0009 "CD-R" 359847 7056
  burner

  # Act
  run disk_test_run enban write "${CUE}" --drive "${DRIVE}" --speed 16 <<<"disc.iso"

  # Assert
  local sent
  sent="$(cat "${WORK}/burner.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "-v dev=${DRIVE} -dao speed=16 -eject cuefile=${CUE}" ]]
  [[ "${output}" == *"Done. ${DRIVE} is written as an audio CD and ejected." ]]
}

@test "enban write leaves an audio CD in the drive with --no-eject" {
  # Arrange
  disk_test_drive 000a "CD-RW" 359847 7056
  burner

  # Act
  run disk_test_run enban write "${CUE}" --drive "${DRIVE}" --no-eject <<<"disc.iso"

  # Assert
  local sent
  sent="$(cat "${WORK}/burner.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "-v dev=${DRIVE} -dao cuefile=${CUE}" ]]
  [[ "${output}" == *"Done. ${DRIVE} is written as an audio CD." ]]
}

@test "enban write burns an audio CD only to a blank CD" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  burner

  # Act
  run disk_test_run enban write "${CUE}" --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: an audio CD needs a blank CD-R or CD-RW, and the disc in ${DRIVE} is a DVD-R." ]]
}

@test "enban write says why the audio burn failed" {
  # Arrange
  disk_test_drive 0009 "CD-R" 359847 7056
  burner
  : >"${WORK}/burn.fail"

  # Act
  run disk_test_run enban write "${CUE}" --drive "${DRIVE}" <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: the audio burn to ${DRIVE} failed: Cannot open cue file" ]]
}

@test "enban write burns nothing without the drive's name" {
  # Arrange
  disk_test_drive 0009 "CD-R" 359847 7056
  burner

  # Act
  run disk_test_run enban write "${CUE}" --drive "${DRIVE}" <<<"wrong"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: stopped: nothing was written." ]]
  [[ ! -e "${WORK}/burner.log" ]]
}

@test "enban write says when the CUE sheet is missing" {
  # Arrange
  local cue="${WORK}/gone.cue"

  # Act
  run disk_test_run enban write "${cue}" --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no CUE sheet at ${cue}." ]]
}

@test "enban write burns an audio CD only to a blank disc" {
  # Arrange
  local search_path
  disk_test_drive 0009 "CD-R" 359847 7056
  dd if=/dev/urandom of="${WORK}/image.iso" bs=2048 count=512 2>/dev/null
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="${DRIVE}" -dao "${WORK}/image.iso" >/dev/null 2>&1
  burner

  # Act
  run disk_test_run enban write "${CUE}" --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: the disc in ${DRIVE} is not blank." ]]
}

@test "enban write --test burns an audio CD as a test" {
  # Arrange
  disk_test_drive 0009 "CD-R" 359847 7056
  burner

  # Act
  run disk_test_run enban write "${CUE}" --drive "${DRIVE}" --no-eject --test <<<"disc.iso"

  # Assert
  local sent
  sent="$(cat "${WORK}/burner.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "-v dev=${DRIVE} -dao -dummy cuefile=${CUE}" ]]
  [[ "${output}" == *"Done. the test write to ${DRIVE} ran to the end, and nothing was written." ]]
}

@test "enban write burns an audio CD track at once and leaves it open" {
  # Arrange
  disk_test_drive 0009 "CD-R" 359847 7056
  burner

  # Act
  run disk_test_run enban write "${CUE}" --drive "${DRIVE}" --no-eject --mode tao --no-finalize <<<"disc.iso"

  # Assert
  local sent
  sent="$(cat "${WORK}/burner.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "-v dev=${DRIVE} -tao -multi cuefile=${CUE}" ]]
}

@test "enban write refuses OPC for an audio CD" {
  # Arrange
  local cue="${CUE}"

  # Act
  run disk_test_run enban write "${cue}" --drive "${DRIVE}" --opc </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --opc applies to data discs; the burner calibrates an audio CD on its own." ]]
}
