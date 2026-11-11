#!/usr/bin/env bats
# shellcheck disable=SC2016

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-build.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  SRC="${WORK}/Family_2009"
  OUT="${WORK}/family.iso"
  mkdir -p "${SRC}/sub"
  head -c 3000 /dev/urandom >"${SRC}/notes.txt"
  head -c 70000 /dev/urandom >"${SRC}/sub/photo.bin"
  head -c 12 /dev/urandom >"${SRC}/sub/tiny.dat"
}

teardown() {
  [[ ! -d "${WORK}/mnt" ]] || hdiutil detach "${WORK}/mnt" >/dev/null 2>&1 || true
  rm -rf "${WORK}"
}

sized_files() {
  local found file size
  local -a names
  found="$(cd "$1" && find . -type f)"
  mapfile -t names <<<"${found}"
  local -a rows=()
  for file in "${names[@]}"; do
    size="$(wc -c <"$1/${file}")"
    rows+=("${file#./} ${size//[[:space:]]/}")
  done
  printf '%s\n' "${rows[@]}" | LC_ALL=C sort
}

listed_files() {
  local listing
  listing="$(xorriso -indev "$1" -find / -type f -exec lsdl 2>/dev/null)"
  local rows
  rows="$(awk '{ name = $NF; gsub("\047", "", name); sub("^/", "", name); print name, $5 }' <<<"${listing}")"
  LC_ALL=C sort <<<"${rows}"
}

image_files() {
  case "${ENBAN_TEST_OS}" in
  Darwin)
    mkdir -p "${WORK}/mnt"
    hdiutil attach -readonly -nobrowse -mountpoint "${WORK}/mnt" "$1" >/dev/null || return 1
    sized_files "${WORK}/mnt"
    hdiutil detach "${WORK}/mnt" >/dev/null
    ;;
  *) listed_files "$1" ;;
  esac
}

descriptors() {
  local head found
  dd if="$1" of="${WORK}/head.bin" bs=2048 skip=16 count=16 2>/dev/null
  head="$(LC_ALL=C tr -c '%/@CENSR0-9' ' ' <"${WORK}/head.bin")"
  found=""
  [[ "${head}" != *"%/"[@CE]* ]] || found="joliet "
  [[ "${head}" != *NSR0[23]* ]] || found="${found}udf "
  printf '%s' "${found}"
}

volume_id() {
  local raw
  dd if="$1" of="${WORK}/volume.bin" bs=1 skip=$((16 * 2048 + 40)) count=32 2>/dev/null
  raw="$(tr -d ' \000' <"${WORK}/volume.bin")"
  printf '%s' "${raw}"
}

@test "enban build makes an image with ISO9660, Joliet and UDF that lists every file" {
  # Arrange
  local wanted
  wanted="$(sized_files "${SRC}")"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" </dev/null

  # Assert
  local listed kinds
  listed="$(image_files "${OUT}")"
  kinds="$(descriptors "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${listed}" == "${wanted}" ]]
  [[ "${kinds}" == "joliet udf " ]]
  [[ "${lines[0]}" == "Files         3" ]]
  [[ "${lines[2]}" == "File systems  ISO9660, Joliet, UDF" ]]
  [[ "${lines[3]}" == "Done. ${OUT} is built from ${SRC}." ]]
}

@test "enban build names the volume after the folder, in ISO9660 letters" {
  # Arrange
  local source="${SRC}"

  # Act
  run disk_test_run enban build "${source}" "${OUT}" </dev/null

  # Assert
  local label
  label="$(volume_id "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${label}" == "FAMILY_2009" ]]
}

@test "enban build takes a label and keeps it to ISO9660 letters" {
  # Arrange
  local label_option="--label=Trip to Kyoto, 2024"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" "${label_option}" </dev/null

  # Assert
  local label
  label="$(volume_id "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${label}" == "TRIP_TO_KYOTO__2024" ]]
}

@test "enban build leaves out the file systems --fs does not name" {
  # Arrange
  local option=--fs

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" "${option}" iso9660 </dev/null

  # Assert
  local kinds
  kinds="$(descriptors "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${kinds}" == "" ]]
  [[ "${lines[2]}" == "File systems  ISO9660" ]]
}

@test "enban build without UDF needs no genisoimage on Linux" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS builds with hdiutil"
  local farm
  farm="$(disk_test_farm genisoimage)"

  # Act
  run disk_test_run_path "${farm}" enban build "${SRC}" "${OUT}" --fs iso9660,joliet </dev/null

  # Assert
  local kinds
  kinds="$(descriptors "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${kinds}" == "joliet " ]]
}

@test "enban build says UDF on Linux needs genisoimage" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS builds with hdiutil"
  local farm
  farm="$(disk_test_farm genisoimage)"

  # Act
  run disk_test_run_path "${farm}" enban build "${SRC}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: UDF on Linux needs genisoimage. install it, or leave udf out of --fs." ]]
  [[ ! -e "${OUT}" ]]
}

@test "enban build reports a tool that fails and leaves no image" {
  # Arrange
  disk_test_shim hdiutil "exit 1"
  disk_test_shim xorriso "exit 1"
  disk_test_shim genisoimage "exit 1"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to build ${OUT} from ${SRC}." ]]
  [[ ! -e "${OUT}" ]]
}

@test "enban build never overwrites a file" {
  # Arrange
  printf 'keep\n' >"${OUT}"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" </dev/null

  # Assert
  local kept
  kept="$(cat "${OUT}")"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${OUT} already exists." ]]
  [[ "${kept}" == "keep" ]]
}

@test "enban build needs a folder to read" {
  # Arrange
  local source="${WORK}/missing"

  # Act
  run disk_test_run enban build "${source}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no folder at ${source}." ]]
}

@test "enban build refuses a file system it does not know" {
  # Arrange
  local option=--fs

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" "${option}" iso9660,hfs </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --fs takes iso9660, joliet and udf, got: hfs" ]]
}

@test "enban build needs ISO9660 among the file systems" {
  # Arrange
  local option=--fs

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" "${option}" joliet,udf </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --fs needs iso9660, which every drive and system can read." ]]
}

@test "enban build refuses a label longer than 32 characters" {
  # Arrange
  local label
  label="$(printf 'x%.0s' {1..33})"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --label "${label}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --label takes up to 32 characters, got 33." ]]
}

@test "enban build draws its result with gum" {
  # Arrange
  export ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  grep -qF -- "Done. ${OUT} is built from ${SRC}." "${WORK}/gum.log"
}

@test "enban build without an output stops with the usage hint" {
  # Arrange
  local source="${SRC}"

  # Act
  run disk_test_run enban build "${source}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: build needs a folder and an image file to create. run 'enban help' for usage." ]]
}

@test "enban build refuses an option that only write takes" {
  # Arrange
  local option=--speed

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" "${option}" 8 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--speed' works only with write and discovery. run 'enban help' for usage." ]]
}

@test "write refuses --fs, which only build takes" {
  # Arrange
  local option=--fs

  # Act
  run disk_test_run enban write "${OUT}" --drive /dev/sr0 "${option}" iso9660 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--fs' works only with build. run 'enban help' for usage." ]]
}

quoted() {
  local text="$1"
  printf "'%s'" "${text//\'/\'\\\'\'}"
}

layout_call() {
  local format="" words="" name source out
  while [[ $# -gt 0 ]]; do
    name="$(quoted "$1")"
    source="$(quoted "$2")"
    format="${format}%s\\t%s\\t0\\t0\\t0\\n"
    words="${words} ${name} ${source}"
    shift 2
  done
  out="$(quoted "${OUT}")"
  printf 'DISK_BUILD_LAYOUT="$(printf %s%s)" DISK_BUILD_OUT=%s; disk_build_run' "'${format}'" "${words}" "${out}"
}

@test "a layout puts each entry at the root of the image under its disc name" {
  # Arrange
  local call wanted
  call="$(layout_call pictures "${SRC}/sub" readme.txt "${SRC}/notes.txt")"
  mkdir -p "${WORK}/wanted/pictures"
  cp "${SRC}/sub/photo.bin" "${SRC}/sub/tiny.dat" "${WORK}/wanted/pictures/"
  cp "${SRC}/notes.txt" "${WORK}/wanted/readme.txt"
  wanted="$(sized_files "${WORK}/wanted")"

  # Act
  run disk_test_call eval "${call}"

  # Assert
  local listed label
  listed="$(image_files "${OUT}")"
  label="$(volume_id "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${listed}" == "${wanted}" ]]
  [[ "${label}" == "PICTURES" ]]
  [[ "${lines[0]}" == "Files         3" ]]
  [[ "${lines[3]}" == "Done. ${OUT} is built from 2 entries." ]]
}

@test "a layout stops at an entry whose source is gone" {
  # Arrange
  local call
  call="$(layout_call pictures "${WORK}/gone")"

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no file or folder at ${WORK}/gone." ]]
  [[ ! -e "${OUT}" ]]
}

@test "a layout keeps an equals sign in a name and a path" {
  # Arrange
  local call wanted
  mkdir -p "${WORK}/a=b"
  cp "${SRC}/notes.txt" "${WORK}/a=b/x=y.txt"
  call="$(layout_call 'one=two' "${WORK}/a=b")"
  mkdir -p "${WORK}/wanted/one=two"
  cp "${SRC}/notes.txt" "${WORK}/wanted/one=two/x=y.txt"
  wanted="$(sized_files "${WORK}/wanted")"

  # Act
  run disk_test_call eval "${call}"

  # Assert
  local listed
  listed="$(image_files "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${listed}" == "${wanted}" ]]
}
