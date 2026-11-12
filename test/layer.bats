#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-layer.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  IMAGE="${WORK}/movie.iso"
  mkdir -p "${WORK}/files/VIDEO_TS"
}

teardown() {
  rm -rf "${WORK}"
}

word() {
  printf '\\%03o\\%03o\\%03o\\%03o' $(($1 >> 24 & 255)) $(($1 >> 16 & 255)) $(($1 >> 8 & 255)) $(($1 & 255))
}

title_set() {
  local set="$1"
  local ifo="${WORK}/files/VIDEO_TS/$1_0.IFO"
  local title="$2"
  shift 2
  local last=$((7 + 12 * $#))
  local cells="" start first final title_word table_word last_word
  for start in "$@"; do
    first="$(word "${start}")"
    final="$(word $((start + 9)))"
    cells="${cells}\\000\\001\\001\\000${first}${final}"
  done
  title_word="$(word "${title}")"
  table_word="$(word 1)"
  last_word="$(word "${last}")"
  {
    printf 'DVDVIDEO-VTS'
    head -c 184 /dev/zero
    printf '%b' "${title_word}"
    head -c 24 /dev/zero
    printf '%b' "${table_word}"
    head -c 1820 /dev/zero
    printf '%b' "\\000\\001\\000\\000${last_word}${cells}"
  } >"${ifo}"
  printf 'video' >"${WORK}/files/VIDEO_TS/${set}_1.VOB"
}

image_of() {
  local search_path
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as mkisofs -quiet -o "${IMAGE}" "${WORK}/files" 2>/dev/null
  dd if=/dev/zero of="${IMAGE}" bs=2048 seek="$1" count=0 2>/dev/null
}

ifo_sector() {
  xorriso -indev "${IMAGE}" -find "/VIDEO_TS/$1_0.IFO" -exec report_lba -- >"${WORK}/lba.txt" 2>/dev/null
  sed -n "s/^File data lba: *0 , *\([0-9]*\) ,.*/\1/p" "${WORK}/lba.txt"
}

@test "enban layerbreak picks the first cell start past the middle" {
  # Arrange
  title_set VTS_01 2 100 1199000 1300000 1500000
  image_of 2400000
  local ifo expected
  ifo="$(ifo_sector VTS_01)"
  expected=$((ifo + 2 + 1300000))

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "Layer break at sector ${expected}, a cell start in VTS_01. layer 0 holds ${expected} of 2400000 sectors." ]]
}

@test "enban layerbreak never puts more on layer 0 than it holds" {
  # Arrange
  title_set VTS_01 2 100 2100000
  image_of 4000000

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "No cell starts between the middle and sector 2086912, so the layer break falls at sector 2000000, the middle." ]]
}

@test "enban layerbreak falls at the middle of an image with no DVD-Video" {
  # Arrange
  printf 'data' >"${WORK}/files/a.dat"
  rmdir "${WORK}/files/VIDEO_TS"
  image_of 3000001

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "No cell starts between the middle and sector 2086912, so the layer break falls at sector 1500001, the middle." ]]
}

@test "enban layerbreak skips a title set with an empty cell table" {
  # Arrange
  title_set VTS_01 2
  image_of 2400000

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"falls at sector 1200000, the middle." ]]
}

middle_image() {
  printf 'data' >"${WORK}/files/a.dat"
  rmdir "${WORK}/files/VIDEO_TS"
  image_of 3000001
}

be_word() {
  local value
  value="$(od -An -tu1 -j "$2" -N 4 "$1")"
  awk '{ print $1 * 16777216 + $2 * 65536 + $3 * 256 + $4 }' <<<"${value}"
}

le_word() {
  local value
  value="$(od -An -tu4 -j "$2" -N 4 "$1")"
  printf '%s' "${value//[[:space:]]/}"
}

@test "enban layerbreak --dvd-file writes the layer break for ImgBurn" {
  # Arrange
  middle_image

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" --dvd-file </dev/null

  # Assert
  local written
  written="$(od -An -tx1 -v "${WORK}/movie.dvd")"
  [[ "${status}" -eq 0 ]]
  [[ "${written//[[:space:]]/}" == "4c61796572427265616b3d313530303030310d0a6d6f7669652e69736f0d0a" ]]
  [[ "${lines[1]}" == "Wrote ${WORK}/movie.dvd, which points ImgBurn and other burners at the layer break." ]]
}

@test "enban layerbreak --mds-file writes a dual-layer descriptor" {
  # Arrange
  middle_image

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" --mds-file </dev/null

  # Assert
  local mds="${WORK}/movie.mds" signature layer_end area_end second_end length name
  signature="$(head -c 16 "${mds}")"
  layer_end="$(be_word "${mds}" $((88 + 4 + 2048 + 12)))"
  area_end="$(be_word "${mds}" $((88 + 4 + 2048 + 8)))"
  second_end="$(be_word "${mds}" $((88 + 4100 + 4 + 2048 + 12)))"
  length="$(le_word "${mds}" 8292)"
  name="$(dd if="${mds}" bs=1 skip=8408 count=9 2>/dev/null)"
  [[ "${status}" -eq 0 ]]
  [[ "${signature}" == "MEDIA DESCRIPTOR" ]]
  [[ "${layer_end}" == "$((196608 + 1500001 - 1))" ]]
  [[ "${area_end}" == "$((16777215 - (196608 + 1500001 - 1) + 1500000 - 1))" ]]
  [[ "${second_end}" == "${layer_end}" ]]
  [[ "${length}" == "3000001" ]]
  [[ "${name}" == "movie.iso" ]]
}

@test "enban layerbreak keeps a DVD file it replaces" {
  # Arrange
  middle_image
  printf 'old' >"${WORK}/movie.dvd"

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" --dvd-file </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "$(<"${WORK}/movie.dvd.bak")" == "old" ]]
  [[ "${output}" == *"The earlier ${WORK}/movie.dvd is kept as ${WORK}/movie.dvd.bak."* ]]
}

@test "enban layerbreak stops when every backup name is taken" {
  # Arrange
  local n
  middle_image
  printf 'old' >"${WORK}/movie.mds"
  : >"${WORK}/movie.mds.bak"
  for n in $(seq 1 99); do : >"${WORK}/movie.mds.bak.${n}"; done

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" --mds-file </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: stopped: ${WORK}/movie.mds.bak to .bak.99 all exist, so there is no room to keep ${WORK}/movie.mds." ]]
  [[ "$(<"${WORK}/movie.mds")" == "old" ]]
}

@test "enban layerbreak writes no layer file for a single-layer image" {
  # Arrange
  printf 'CD001' >"${WORK}/magic"
  head -c 65536 /dev/zero >"${IMAGE}"
  dd if="${WORK}/magic" of="${IMAGE}" bs=1 seek=32769 conv=notrunc 2>/dev/null

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" --dvd-file </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[1]}" == "enban: --dvd-file and --mds-file need an image that spans two layers." ]]
  [[ ! -e "${WORK}/movie.dvd" ]]
}

@test "write refuses --dvd-file, which only layerbreak takes" {
  # Arrange
  local option=--dvd-file

  # Act
  run disk_test_run enban write "${IMAGE}" --drive /dev/sr0 "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--dvd-file' works only with layerbreak. run 'enban help' for usage." ]]
}

@test "enban layerbreak says an image that fits one layer needs no break" {
  # Arrange
  printf 'CD001' >"${WORK}/magic"
  head -c 65536 /dev/zero >"${IMAGE}"
  dd if="${WORK}/magic" of="${IMAGE}" bs=1 seek=32769 conv=notrunc 2>/dev/null

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "${IMAGE} is 32 sectors and fits on one layer, so it needs no layer break." ]]
}

@test "enban layerbreak refuses an image larger than a dual-layer DVD" {
  # Arrange
  printf 'CD001' >"${WORK}/magic"
  dd if=/dev/zero of="${IMAGE}" bs=2048 seek=4173825 count=0 2>/dev/null
  dd if="${WORK}/magic" of="${IMAGE}" bs=1 seek=32769 conv=notrunc 2>/dev/null

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${IMAGE} is 4173825 sectors, more than a dual-layer DVD holds." ]]
}

@test "enban layerbreak refuses a file that is not an ISO image" {
  # Arrange
  head -c 65536 /dev/zero >"${IMAGE}"

  # Act
  run disk_test_run enban layerbreak "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${IMAGE} is not an ISO image." ]]
}

@test "enban layerbreak says when the image is missing" {
  # Arrange
  local gone="${WORK}/gone.iso"

  # Act
  run disk_test_run enban layerbreak "${gone}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no image at ${gone}." ]]
}

@test "enban layerbreak needs an image" {
  # Arrange
  local command=layerbreak

  # Act
  run disk_test_run enban "${command}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: layerbreak needs an image. run 'enban help' for usage." ]]
}

@test "a file past 4 GiB reports its whole size" {
  # Arrange
  dd if=/dev/zero of="${WORK}/large.img" bs=1 count=0 seek=4915200123 2>/dev/null

  # Act
  run disk_test_call disk_file_bytes "${WORK}/large.img"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "4915200123" ]]
}
