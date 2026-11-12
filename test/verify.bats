#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-verify.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  IMAGE="${WORK}/image.iso"
  DISC="${WORK}/disc.iso"
  DRIVE="stdio:${DISC}"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=512 2>/dev/null
  : >"${DISC}"
}

teardown() {
  rm -rf "${WORK}"
}

written_dvd() {
  local search_path
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="${DRIVE}" -dao "${IMAGE}" >/dev/null 2>&1
}

change_sector() {
  printf 'XX' | dd of="${DISC}" bs=1 seek=$(($1 * 2048 + 7)) conv=notrunc 2>/dev/null
}

@test "enban verify finds a disc that matches its image" {
  # Arrange
  written_dvd

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "Readable     512 of 512 sectors" ]]
  [[ "${lines[1]}" == "Miscompares  0" ]]
  [[ "${lines[2]}" == "Unreadable   0" ]]
  [[ "${lines[3]}" == "Done. ${DRIVE} matches ${IMAGE} byte for byte." ]]
}

@test "enban verify names the first sector that differs from the image" {
  # Arrange
  written_dvd
  change_sector 100
  change_sector 300

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[1]}" == "Miscompares  2" ]]
  [[ "${lines[3]}" == "enban: the disc in ${DRIVE} differs from ${IMAGE}, first at sector 100." ]]
}

@test "enban verify without an image reads every sector of the disc, padding included" {
  # Arrange
  written_dvd

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "Readable     662 of 662 sectors" ]]
  [[ "${lines[3]}" == "Done. every sector of ${DRIVE} can be read." ]]
}

@test "enban verify names the first sector it cannot read" {
  # Arrange
  written_dvd
  disk_test_shim dd "case \" \$* \" in *\" if=\"*) \"\${REAL}\" if='${DRIVE#stdio:}' bs=2048 count=200; exit 1 ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[0]}" == "Readable     200 of 662 sectors" ]]
  [[ "${lines[2]}" == "Unreadable   462" ]]
  [[ "${lines[3]}" == "enban: 462 sectors of the disc in ${DRIVE} could not be read, from sector 200." ]]
}

@test "enban verify refuses a disc with no data" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: the disc in ${DRIVE} holds no data to verify." ]]
}

@test "enban verify refuses an image larger than the data on the disc" {
  # Arrange
  written_dvd
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=700 2>/dev/null

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${IMAGE} has 700 sectors and the disc in ${DRIVE} holds 662." ]]
}

@test "enban verify refuses a file that is not a disc image" {
  # Arrange
  written_dvd
  printf 'not an image\n' >"${IMAGE}"

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${IMAGE} is not a disc image: its size is not a whole number of 2048-byte sectors." ]]
}

@test "enban verify draws its result with gum" {
  # Arrange
  written_dvd
  export ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log"

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  grep -qF -- "Done. ${DRIVE} matches ${IMAGE} byte for byte." "${WORK}/gum.log"
}

@test "enban verify stops on macOS, where reading a drive is not supported yet" {
  # Arrange
  local drive=/dev/disk4

  # Act
  ENBAN_OS=Darwin run disk_test_run enban verify --drive "${drive}" "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: on macOS name a drive like IODVDServices/0 or IOCompactDiscServices/0, or an image like stdio:disc.iso, so verify cannot use ${drive}." ]]
}

@test "enban verify without --drive stops with the usage hint" {
  # Arrange
  local image="${IMAGE}"

  # Act
  run disk_test_run enban verify "${image}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: verify needs --drive. run 'enban help' for usage." ]]
}

@test "enban verify refuses --no-verify" {
  # Arrange
  local option=--no-verify

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--no-verify' works only with write, read and queue. run 'enban help' for usage." ]]
}

@test "enban verify --ignore-miscompares reports a sector that differs and passes" {
  # Arrange
  written_dvd
  change_sector 9

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" "${IMAGE}" --ignore-miscompares </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"enban: warning: the disc in ${DRIVE} differs from ${IMAGE}, first at sector 9, ignored as asked."* ]]
  [[ "${output}" == *"Done. every sector of ${DRIVE} can be read, and 1 differ from ${IMAGE}." ]]
}

@test "enban verify --retries reads the disc again after a short read" {
  # Arrange
  written_dvd
  printf '1\n' >"${WORK}/short"
  disk_test_shim dd "case \" \$* \" in
*\" if=${DISC} \"*)
  if [ \"\$(cat '${WORK}/short')\" -gt 0 ]; then
    printf '0\\n' >'${WORK}/short'
    set -- \"\$@\" count=10
  fi
  ;;
esac
exec \"\${REAL}\" \"\$@\""

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" --retries 1 </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Verifying ${DRIVE} again, try 2 of 2."* ]]
  [[ "${output}" == *"Done. every sector of ${DRIVE} can be read." ]]
}

@test "enban verify sets the drive's read speed first" {
  # Arrange
  written_dvd
  disk_test_raw

  # Act
  run disk_test_run enban verify --drive "${DRIVE}" --speed max </dev/null

  # Assert
  local sent
  sent="$(sed -n '1p' "${WORK}/sg_raw.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "${DISC} bb 00 ff ff ff ff 00 00 00 00 00 00" ]]
}

@test "--ignore-miscompares works only with verify" {
  # Arrange
  local option=--ignore-miscompares

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/out.iso" "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--ignore-miscompares' works only with verify. run 'enban help' for usage." ]]
}
