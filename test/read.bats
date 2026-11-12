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
  written_dvd

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" --no-verify </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DRIVE} is read into ${OUT}." ]]
}

@test "enban read refuses a disc with no data" {
  # Arrange
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
  written_dvd
  disk_test_shim dd "case \" \$* \" in *\" of=\"*)
  \"\${REAL}\" \"\$@\" || exit 1
  flip=X
  [ \"\$(od -An -c -j 100 -N 1 '${OUT}' | tr -d ' ')\" != X ] || flip=Y
  printf '%s' \"\${flip}\" | \"\${REAL}\" of='${OUT}' bs=1 seek=100 conv=notrunc 2>/dev/null
  ;;
*) exec \"\${REAL}\" \"\$@\" ;;
esac"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the copy in ${OUT} does not match the disc in ${DRIVE}." ]]
}

@test "enban read draws its result with gum" {
  # Arrange
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
  [[ "${output}" == "enban: on macOS name a drive like IODVDServices/0 or IOCompactDiscServices/0, or an image like stdio:disc.iso, so read cannot use ${drive}." ]]
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
  local option=--copies

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" "${option}" 2 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--copies' works only with write. run 'enban help' for usage." ]]
}

failing_reads() {
  printf '%s\n' "$1" >"${WORK}/fails"
  disk_test_shim dd "case \" \$* \" in
*\" if=${DISC} \"*\" conv=noerror,sync \"*) \"\${REAL}\" \"\$@\"; printf 'dd: error reading %s: Input/output error\\n' '${DISC}' '${DISC}' >&2; exit 0 ;;
*\" if=${DISC} of=${OUT} \"*)
  left=\"\$(cat '${WORK}/fails')\"
  if [ \"\${left}\" -gt 0 ]; then printf '%s\\n' \"\$((left - 1))\" >'${WORK}/fails'; exit 1; fi
  ;;
esac
exec \"\${REAL}\" \"\$@\""
}

@test "enban read prints the MD5 of the image beside its SHA-256" {
  # Arrange
  written_dvd

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" </dev/null

  # Assert
  local md5
  md5="$(md5sum "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"MD5      ${md5%% *}"* ]]
}

@test "enban read --cue writes a CUE sheet beside the image" {
  # Arrange
  written_dvd

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" --cue </dev/null

  # Assert
  local cue
  cue="$(cat "${WORK}/copy.cue")"
  [[ "${status}" -eq 0 ]]
  [[ "${cue}" == "$(printf 'FILE "copy.iso" BINARY\n  TRACK 01 MODE1/2048\n    INDEX 01 00:00:00')" ]]
}

@test "enban read --retries reads again after a failed read" {
  # Arrange
  written_dvd
  failing_reads 2

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" --retries 2 </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Reading ${DRIVE} again, try 3 of 3."* ]]
  [[ "${output}" == *"Done. ${DRIVE} is read into ${OUT} and verified." ]]
}

half_reads() {
  disk_test_shim dd "case \" \$* \" in *\" if=${DISC} of=${OUT} \"*) head -c 4096 /dev/zero >'${OUT}'; exit 1 ;; esac; exec \"\${REAL}\" \"\$@\""
}

@test "enban read deletes the half-read image when it fails" {
  # Arrange
  written_dvd
  half_reads

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[0]}" == "Deleted the half-read ${OUT}." ]]
  [[ "${lines[1]}" == "enban: unable to read ${DRIVE} into ${OUT}." ]]
  [[ ! -e "${OUT}" ]]
}

@test "enban read keeps the half-read image when the settings say so" {
  # Arrange
  written_dvd
  half_reads
  export ENBAN_CONFIG="${WORK}/config"
  mkdir -p "${ENBAN_CONFIG}"
  printf 'event_clean=no\n' >"${ENBAN_CONFIG}/settings"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[0]}" == "The half-read ${OUT} is kept." ]]
  [[ -s "${OUT}" ]]
}

@test "enban read stops once its retries run out" {
  # Arrange
  written_dvd
  failing_reads 5

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" --retries 1 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: unable to read ${DRIVE} into ${OUT}." ]]
}

@test "enban read --ignore-errors keeps going and counts the unreadable sectors" {
  # Arrange
  written_dvd
  failing_reads 9

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" --ignore-errors </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"enban: warning: 2 sectors of ${DRIVE} could not be read and are zeros in ${OUT}."* ]]
  [[ "${output}" == *"Done. ${DRIVE} is read into ${OUT}." ]]
}

@test "enban read sets the drive's read speed first" {
  # Arrange
  written_dvd
  disk_test_raw

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" --speed 4 </dev/null

  # Assert
  local sent
  sent="$(sed -n '1p' "${WORK}/sg_raw.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "${DISC} bb 00 15 a4 ff ff 00 00 00 00 00 00" ]]
}

@test "enban read --retries takes 0 to 99 and --cue only works with read" {
  # Arrange
  local retries=abc

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" --retries "${retries}" </dev/null

  # Assert
  local other
  other="$(disk_test_run enban write "${OUT}" --drive "${DRIVE}" --cue </dev/null 2>&1 || true)"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --retries must be a whole number from 0 to 99, got: abc" ]]
  [[ "${other}" == "enban: option '--cue' works only with read. run 'enban help' for usage." ]]
}

written_cd() {
  local search_path
  disk_test_drive 0009 "CD-R" 359844 7056
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="${DRIVE}" -dao "${IMAGE}" >/dev/null 2>&1
  disk_test_raw
}

@test "enban read --ccd copies a CD raw with its subchannel and a CloneCD layout" {
  # Arrange
  written_cd
  local raw="${WORK}/copy.img"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${raw}" --ccd </dev/null

  # Assert
  local main_size sub_size layout
  main_size="$(wc -c <"${raw}")"
  sub_size="$(wc -c <"${WORK}/copy.sub")"
  layout="$(<"${WORK}/copy.ccd")"
  dd if="${raw}" bs=1 skip=$((5 * 2352 + 16)) count=2048 2>/dev/null >"${WORK}/user.bin"
  dd if="${IMAGE}" bs=2048 skip=5 count=1 2>/dev/null >"${WORK}/want.bin"
  [[ "${status}" -eq 0 ]]
  [[ "${main_size//[[:space:]]/}" == "1557024" ]]
  [[ "${sub_size//[[:space:]]/}" == "63552" ]]
  cmp -s "${WORK}/user.bin" "${WORK}/want.bin"
  [[ "${layout}" == $'[CloneCD]\r\nVersion=3\r\n'* ]]
  [[ "${layout}" == *$'Point=0xa2\r\nADR=0x01\r\nControl=0x04\r\nTrackNo=0\r\nAMin=0\r\nASec=0\r\nAFrame=0\r\nALBA=-150\r\nZero=0\r\nPMin=0\r\nPSec=10\r\nPFrame=62\r\nPLBA=662\r\n'* ]]
  [[ "${layout}" == *$'[TRACK 1]\r\nMODE=1\r\nINDEX 1=0\r' ]]
  [[ "${output}" == *"CloneCD  ${WORK}/copy.ccd and ${WORK}/copy.sub"* ]]
  [[ "${output}" == *"Done. ${DRIVE} is read into ${raw} and verified." ]]
}

@test "enban read --ccd needs an image name ending in .img" {
  # Arrange
  written_cd

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${OUT}" --ccd </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --ccd writes a raw CloneCD image, so its name ends in .img, got: ${OUT}" ]]
}

@test "enban read --ccd and --cue do not go together" {
  # Arrange
  written_cd

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/copy.img" --ccd --cue </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --ccd and --cue each write the layout file of the image; choose one." ]]
}

@test "enban read --ccd reads only a CD" {
  # Arrange
  written_dvd

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/copy.img" --ccd </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --ccd reads a CD, and the disc in ${DRIVE} is DVD-R sequential recording." ]]
}

@test "enban read --ccd stops when the layout file already exists" {
  # Arrange
  written_cd
  printf 'mine\n' >"${WORK}/copy.ccd"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/copy.img" --ccd </dev/null

  # Assert
  local kept
  kept="$(<"${WORK}/copy.ccd")"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${WORK}/copy.ccd already exists." ]]
  [[ "${kept}" == "mine" ]]
}

@test "enban read --ccd needs sg_raw" {
  # Arrange
  written_cd
  local farm
  farm="$(disk_test_farm sg_raw)"

  # Act
  run disk_test_run_path "${farm}" enban read --drive "${DRIVE}" "${WORK}/copy.img" --ccd </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --ccd needs sg_raw from sg3-utils to read raw sectors. install it and try again." ]]
}

@test "enban read --ccd tries a bad stretch again, then stops and deletes the half copy" {
  # Arrange
  written_cd
  printf 'bad_lba=20\n' >>"${WORK}/drive.state"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/copy.img" --ccd --retries 1 </dev/null

  # Assert
  local tries
  tries="$(grep -c "be 00 00 00 00 10 00 00 10 f8 00 00" "${WORK}/sg_raw.log" || true)"
  [[ "${status}" -eq 1 ]]
  [[ "${tries}" == "2" ]]
  [[ "${output}" == *"enban: unable to read sectors 16 to 31 of ${DRIVE} into ${WORK}/copy.img." ]]
  [[ ! -e "${WORK}/copy.img" ]]
  [[ ! -e "${WORK}/copy.sub" ]]
}

@test "enban read --ccd --ignore-errors writes zeros for a stretch that will not read" {
  # Arrange
  written_cd
  printf 'bad_lba=20\n' >>"${WORK}/drive.state"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/copy.img" --ccd --ignore-errors </dev/null

  # Assert
  local main_size left
  main_size="$(wc -c <"${WORK}/copy.img")"
  dd if="${WORK}/copy.img" bs=2352 skip=16 count=16 2>/dev/null >"${WORK}/stretch.bin"
  left="$(LC_ALL=C tr -d '\000' <"${WORK}/stretch.bin")"
  [[ "${status}" -eq 0 ]]
  [[ "${main_size//[[:space:]]/}" == "1557024" ]]
  [[ -z "${left}" ]]
  [[ "${output}" == *"enban: warning: sectors 16 to 31 of ${DRIVE} could not be read and are zeros in ${WORK}/copy.img."* ]]
  [[ "${output}" == *"Done. ${DRIVE} is read into ${WORK}/copy.img." ]]
}

@test "enban read --ccd reports a raw copy that does not match the disc" {
  # Arrange
  written_cd
  printf 'flip_after=84\n' >>"${WORK}/drive.state"

  # Act
  run disk_test_run enban read --drive "${DRIVE}" "${WORK}/copy.img" --ccd </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the copy in ${WORK}/copy.img does not match the disc in ${DRIVE}." ]]
}
