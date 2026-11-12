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
  local found file size rows=""
  found="$(cd "$1" && find . -type f)"
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    size="$(wc -c <"$1/${file}")"
    rows="${rows}${file#./} ${size//[[:space:]]/}"$'\n'
  done <<<"${found}"
  printf '%s' "${rows}" | LC_ALL=C sort
}

listed_files() {
  local listing
  listing="$(xorriso -indev "$1" -find / -type f -exec lsdl 2>/dev/null)"
  local rows
  rows="$(awk '{ name = $NF; gsub("\047", "", name); sub("^/", "", name); print name, $5 }' <<<"${listing}")"
  LC_ALL=C sort <<<"${rows}"
}

detach_settled() {
  local try
  for try in 1 2 3 4 5; do
    hdiutil detach "$1" >/dev/null 2>&1 && return 0
    sleep "${try}"
  done
  hdiutil detach -force "$1" >/dev/null
}

image_files() {
  case "${ENBAN_TEST_OS}" in
  Darwin)
    mkdir -p "${WORK}/mnt"
    hdiutil attach -readonly -nobrowse -mountpoint "${WORK}/mnt" "$1" >/dev/null || return 1
    sized_files "${WORK}/mnt"
    detach_settled "${WORK}/mnt"
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

@test "enban build without UDF needs neither genisoimage nor mkisofs" {
  # Arrange
  local farm
  farm="$(disk_test_farm genisoimage mkisofs)"

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
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS builds UDF with mkisofs"
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
  disk_test_shim xorriso "exit 1"
  disk_test_shim genisoimage "exit 1"
  disk_test_shim mkisofs "exit 1"

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
  [[ "${output}" == "enban: option '--speed' works only with write, read, verify and discovery. run 'enban help' for usage." ]]
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

pvd_field() {
  local raw
  dd if="$1" of="${WORK}/field.bin" bs=1 skip=$((16 * 2048 + $2)) count="$3" 2>/dev/null
  raw="$(tr -d '\000' <"${WORK}/field.bin")"
  printf '%s' "${raw%"${raw##*[! ]}"}"
}

@test "enban build records every identifier and the date, the names in capitals" {
  # Arrange
  local -a ids=(--publisher "Franco Family" --preparer Gustavo --application enban
    --system-id Linux --volume-set "Family 2009" --date 20091224180000 --iso-level 3)

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --fs iso9660,joliet "${ids[@]}" </dev/null

  # Assert
  local publisher preparer application system volset created level
  publisher="$(pvd_field "${OUT}" 318 128)"
  preparer="$(pvd_field "${OUT}" 446 128)"
  application="$(pvd_field "${OUT}" 574 128)"
  system="$(pvd_field "${OUT}" 8 32)"
  volset="$(pvd_field "${OUT}" 190 128)"
  created="$(pvd_field "${OUT}" 813 14)"
  [[ "${status}" -eq 0 ]]
  [[ "${publisher}" == "FRANCO FAMILY" ]]
  [[ "${preparer}" == "GUSTAVO" ]]
  [[ "${application}" == "ENBAN" ]]
  [[ "${system}" == "LINUX" ]]
  [[ "${volset}" == "Family 2009" ]]
  [[ "${created}" == "20091224180000" ]]
  [[ "${lines[3]}" == "Publisher     FRANCO FAMILY" ]]
  [[ "${lines[4]}" == "Preparer      GUSTAVO" ]]
  [[ "${lines[5]}" == "Application   ENBAN" ]]
  [[ "${lines[6]}" == "System        LINUX" ]]
  [[ "${lines[7]}" == "Volume set    Family 2009" ]]
  [[ "${lines[8]}" == "Date          20091224180000 UTC" ]]
  [[ "${lines[9]}" == "ISO level     3" ]]
}

@test "enban build records the publisher, preparer and application on macOS, in capitals" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Darwin" ]] || skip "Linux records every field"
  local -a ids=(--publisher Franco --preparer Gustavo --application enban)

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" "${ids[@]}" </dev/null

  # Assert
  local publisher preparer application
  publisher="$(pvd_field "${OUT}" 318 128)"
  preparer="$(pvd_field "${OUT}" 446 128)"
  application="$(pvd_field "${OUT}" 574 128)"
  [[ "${status}" -eq 0 ]]
  [[ "${publisher}" == "FRANCO" ]]
  [[ "${preparer}" == "GUSTAVO" ]]
  [[ "${application}" == "ENBAN" ]]
  [[ "${lines[3]}" == "Publisher     FRANCO" ]]
}

@test "enban build on macOS needs mkisofs from cdrtools for UDF" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Darwin" ]] || skip "Linux builds UDF with genisoimage"
  local farm
  farm="$(disk_test_farm mkisofs)"

  # Act
  run disk_test_run_path "${farm}" enban build "${SRC}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: UDF on macOS needs mkisofs from cdrtools. install it with brew install cdrtools, or leave udf out of --fs." ]]
  [[ ! -e "${OUT}" ]]
}

@test "enban build keeps long names through Rock Ridge on every system" {
  # Arrange
  head -c 100 /dev/urandom >"${SRC}/a-rather-long-file-name.jpeg"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --fs iso9660 </dev/null

  # Assert
  local listed
  listed="$(image_files "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${listed}" == *"a-rather-long-file-name.jpeg 100"* ]]
}

@test "enban build refuses a date with UDF" {
  # Arrange
  local option=--date

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" "${option}" 20091224180000 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --date needs xorriso, and a UDF image is built with genisoimage or mkisofs, which cannot set it. leave udf out of --fs or leave out --date." ]]
  [[ ! -e "${OUT}" ]]
}

@test "enban build refuses a publisher longer than 128 characters" {
  # Arrange
  local publisher
  publisher="$(printf 'p%.0s' {1..129})"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --publisher "${publisher}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --publisher takes up to 128 characters, got 129." ]]
}

@test "enban build refuses a date that is not YYYYMMDDhhmmss" {
  # Arrange
  local date=2009-12-24

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --date "${date}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --date takes YYYYMMDDhhmmss in UTC, such as 20091224180000, got: 2009-12-24" ]]
}

@test "enban build refuses an ISO level outside 1 to 4" {
  # Arrange
  local level=5

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --iso-level "${level}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --iso-level takes 1, 2, 3 or 4, got: 5" ]]
}

@test "write refuses --publisher, which only build takes" {
  # Arrange
  local option=--publisher

  # Act
  run disk_test_run enban write "${OUT}" --drive /dev/sr0 "${option}" Franco </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--publisher' works only with build. run 'enban help' for usage." ]]
}

boot_entry() {
  local catalog platform media count
  catalog="$(od -An -tu4 -j $((17 * 2048 + 71)) -N 4 "$1")"
  catalog="${catalog//[[:space:]]/}"
  platform="$(od -An -tx1 -j $((catalog * 2048 + 1)) -N 1 "$1")"
  media="$(od -An -tx1 -j $((catalog * 2048 + 32)) -N 2 "$1")"
  count="$(od -An -tu2 -j $((catalog * 2048 + 38)) -N 2 "$1")"
  printf '%s %s %s' "${platform//[[:space:]]/}" "${media//[[:space:]]/}" "${count//[[:space:]]/}"
}

boot_table() {
  local catalog lba pvd
  catalog="$(od -An -tu4 -j $((17 * 2048 + 71)) -N 4 "$1")"
  catalog="${catalog//[[:space:]]/}"
  lba="$(od -An -tu4 -j $((catalog * 2048 + 40)) -N 4 "$1")"
  lba="${lba//[[:space:]]/}"
  pvd="$(od -An -tu4 -j $((lba * 2048 + 8)) -N 4 "$1")"
  printf '%s' "${pvd//[[:space:]]/}"
}

mbr_image() {
  head -c 1048576 /dev/zero >"$1"
  printf '\200\000\002\000\006\037\077\000\001\000\000\000\377\007\000\000' | dd of="$1" bs=1 seek=446 conv=notrunc 2>/dev/null
  printf '\125\252' | dd of="$1" bs=1 seek=510 conv=notrunc 2>/dev/null
}

@test "enban build makes a bootable image and keeps the boot file hidden and unchanged" {
  # Arrange
  local wanted
  head -c 2048 /dev/urandom >"${WORK}/boot.bin"
  cp -f "${WORK}/boot.bin" "${WORK}/boot.orig"
  wanted="$(sized_files "${SRC}")"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --fs iso9660,joliet --boot "${WORK}/boot.bin" </dev/null

  # Assert
  local entry listed
  entry="$(boot_entry "${OUT}")"
  listed="$(image_files "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${entry}" == "00 8800 4" ]]
  [[ "${listed}" == "${wanted}" ]]
  cmp -s "${WORK}/boot.bin" "${WORK}/boot.orig"
  [[ "${lines[3]}" == "Boot          boot.bin, no emulation, x86" ]]
  [[ ! -e "${OUT}.boot" ]]
}

@test "enban build boots a floppy image with floppy emulation" {
  # Arrange
  head -c 1474560 /dev/zero >"${WORK}/floppy.img"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --fs iso9660 --boot "${WORK}/floppy.img" --emulation floppy </dev/null

  # Assert
  local entry
  entry="$(boot_entry "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${entry}" == "00 8802 1" ]]
  [[ "${lines[3]}" == "Boot          floppy.img, floppy emulation, x86" ]]
}

@test "enban build boots a disk image with hard disk emulation" {
  # Arrange
  mbr_image "${WORK}/disk.img"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --fs iso9660 --boot "${WORK}/disk.img" --emulation hard-disk </dev/null

  # Assert
  local entry
  entry="$(boot_entry "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${entry}" == "00 8804 1" ]]
  [[ "${lines[3]}" == "Boot          disk.img, hard disk emulation, x86" ]]
}

@test "enban build sets the platform, the sectors to load and the boot info table" {
  # Arrange
  head -c 4096 /dev/zero >"${WORK}/boot.bin"
  local -a entry_options=(--boot "${WORK}/boot.bin" --platform mac --load-sectors 8 --boot-info-table)

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --fs iso9660 "${entry_options[@]}" </dev/null

  # Assert
  local entry table source
  entry="$(boot_entry "${OUT}")"
  table="$(boot_table "${OUT}")"
  source="$(od -An -tu4 -j 8 -N 4 "${WORK}/boot.bin")"
  [[ "${status}" -eq 0 ]]
  [[ "${entry}" == "02 8800 8" ]]
  [[ "${table}" == "16" ]]
  [[ "${source//[[:space:]]/}" == "0" ]]
}

@test "enban build boots PowerPC" {
  # Arrange
  head -c 2048 /dev/zero >"${WORK}/boot.bin"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --fs iso9660 --boot "${WORK}/boot.bin" --platform ppc </dev/null

  # Assert
  local entry
  entry="$(boot_entry "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${entry}" == "01 8800 4" ]]
}

@test "enban build makes a bootable UDF image for EFI on Linux" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS boots through xorriso, which writes no UDF"
  local wanted
  head -c 2048 /dev/zero >"${WORK}/boot.bin"
  wanted="$(sized_files "${SRC}")"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --boot "${WORK}/boot.bin" --platform efi </dev/null

  # Assert
  local entry listed kinds
  entry="$(boot_entry "${OUT}")"
  listed="$(image_files "${OUT}")"
  kinds="$(descriptors "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${entry}" == "ef 8800 4" ]]
  [[ "${listed}" == "${wanted}" ]]
  [[ "${kinds}" == "joliet udf " ]]
}

@test "enban build on Linux refuses PowerPC with UDF" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS refuses UDF with any boot image"
  head -c 2048 /dev/zero >"${WORK}/boot.bin"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --boot "${WORK}/boot.bin" --platform ppc </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --platform ppc needs xorriso, and a UDF image on Linux is built with genisoimage, which boots x86 and efi only. leave udf out of --fs." ]]
}

@test "enban build needs --boot for a boot entry option" {
  # Arrange
  local option=--emulation

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" "${option}" floppy </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --emulation needs --boot FILE, the boot image." ]]
}

@test "enban build stops when the boot image is not there" {
  # Arrange
  local boot="${WORK}/none.bin"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --boot "${boot}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no boot image to read at ${boot}." ]]
}

@test "enban build refuses an emulation it does not know" {
  # Arrange
  head -c 2048 /dev/zero >"${WORK}/boot.bin"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --boot "${WORK}/boot.bin" --emulation zip </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --emulation takes none, floppy or hard-disk, got: zip" ]]
}

@test "enban build refuses a floppy image of the wrong size" {
  # Arrange
  head -c 2048 /dev/zero >"${WORK}/boot.bin"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --boot "${WORK}/boot.bin" --emulation floppy </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: a floppy boot image holds 1228800, 1474560 or 2949120 bytes, and ${WORK}/boot.bin holds 2048." ]]
}

@test "enban build refuses a hard disk image with no master boot record" {
  # Arrange
  head -c 4096 /dev/zero >"${WORK}/boot.bin"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --boot "${WORK}/boot.bin" --emulation hard-disk </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: a hard disk boot image starts with a master boot record, and ${WORK}/boot.bin has none." ]]
}

@test "enban build refuses a platform it does not know" {
  # Arrange
  head -c 2048 /dev/zero >"${WORK}/boot.bin"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --boot "${WORK}/boot.bin" --platform arm </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --platform takes x86, efi, ppc or mac, got: arm" ]]
}

@test "enban build loads sectors only with no emulation" {
  # Arrange
  head -c 1474560 /dev/zero >"${WORK}/floppy.img"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --boot "${WORK}/floppy.img" --emulation floppy --load-sectors 4 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --load-sectors works with --emulation none; a floppy or hard disk image is loaded whole." ]]
}

@test "enban build refuses more than 65535 sectors to load" {
  # Arrange
  head -c 2048 /dev/zero >"${WORK}/boot.bin"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --boot "${WORK}/boot.bin" --load-sectors 70000 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --load-sectors takes a whole number from 1 to 65535, got: 70000" ]]
}

@test "enban build refuses sectors to load that are not a number" {
  # Arrange
  head -c 2048 /dev/zero >"${WORK}/boot.bin"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --boot "${WORK}/boot.bin" --load-sectors 4k </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --load-sectors takes a whole number from 1 to 65535, got: 4k" ]]
}

@test "write refuses --boot, which only build takes" {
  # Arrange
  local option=--boot

  # Act
  run disk_test_run enban write "${OUT}" --drive /dev/sr0 "${option}" boot.bin </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--boot' works only with build. run 'enban help' for usage." ]]
}

put_bytes() {
  printf '%b' "$3" | dd of="$1" bs=1 seek="$2" conv=notrunc 2>/dev/null
}

be32() {
  printf '\\%03o\\%03o\\%03o\\%03o' $(($1 >> 24 & 255)) $(($1 >> 16 & 255)) $(($1 >> 8 & 255)) $(($1 & 255))
}

put_be32() {
  local bytes
  bytes="$(be32 "$3")"
  put_bytes "$1" "$2" "${bytes}"
}

video_ts() {
  local dir="$1/VIDEO_TS"
  mkdir -p "${dir}"
  head -c 4096 /dev/zero >"${dir}/VIDEO_TS.IFO"
  put_bytes "${dir}/VIDEO_TS.IFO" 0 DVDVIDEO-VMG
  put_be32 "${dir}/VIDEO_TS.IFO" 12 6
  put_be32 "${dir}/VIDEO_TS.IFO" 28 1
  put_bytes "${dir}/VIDEO_TS.IFO" 62 '\000\001'
  put_be32 "${dir}/VIDEO_TS.IFO" 192 2
  put_be32 "${dir}/VIDEO_TS.IFO" 196 1
  put_bytes "${dir}/VIDEO_TS.IFO" 2048 '\000\001'
  put_bytes "${dir}/VIDEO_TS.IFO" 2062 '\001'
  put_be32 "${dir}/VIDEO_TS.IFO" 2064 7
  head -c 6144 /dev/urandom >"${dir}/VIDEO_TS.VOB"
  cp -f "${dir}/VIDEO_TS.IFO" "${dir}/VIDEO_TS.BUP"
  head -c 4096 /dev/zero >"${dir}/VTS_01_0.IFO"
  put_bytes "${dir}/VTS_01_0.IFO" 0 DVDVIDEO-VTS
  put_be32 "${dir}/VTS_01_0.IFO" 12 8
  put_be32 "${dir}/VTS_01_0.IFO" 28 1
  put_be32 "${dir}/VTS_01_0.IFO" 192 2
  put_be32 "${dir}/VTS_01_0.IFO" 196 4
  put_be32 "${dir}/VTS_01_0.IFO" 224 1
  put_bytes "${dir}/VTS_01_0.IFO" 2048 '\000\001'
  put_be32 "${dir}/VTS_01_0.IFO" 2052 31
  put_bytes "${dir}/VTS_01_0.IFO" 2056 '\000\001\001\000'
  put_be32 "${dir}/VTS_01_0.IFO" 2060 0
  put_be32 "${dir}/VTS_01_0.IFO" 2064 1
  put_bytes "${dir}/VTS_01_0.IFO" 2068 '\000\001\002\000'
  put_be32 "${dir}/VTS_01_0.IFO" 2072 2
  put_be32 "${dir}/VTS_01_0.IFO" 2076 2
  head -c 4096 /dev/urandom >"${dir}/VTS_01_0.VOB"
  head -c 4096 /dev/urandom >"${dir}/VTS_01_1.VOB"
  head -c 2048 /dev/urandom >"${dir}/VTS_01_2.VOB"
  cp -f "${dir}/VTS_01_0.IFO" "${dir}/VTS_01_0.BUP"
}

video_order() {
  local report rows sorted
  report="$(xorriso -indev "$1" -find /VIDEO_TS -type f -exec report_lba -- 2>/dev/null)"
  rows="$(sed -n "s/^File data lba: *0 , *\([0-9]*\) ,.*'\/VIDEO_TS\/\(.*\)'\$/\1 \2/p" <<<"${report}")"
  sorted="$(sort -n <<<"${rows}")"
  awk '{ printf "%s ", $2 }' <<<"${sorted}"
}

player_order() {
  printf '%s ' VIDEO_TS.IFO VIDEO_TS.VOB VIDEO_TS.BUP VTS_01_0.IFO VTS_01_0.VOB VTS_01_1.VOB VTS_01_2.VOB VTS_01_0.BUP
}

@test "enban build --dvd-video lays out VIDEO_TS in the order a player reads it" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || command -v mkisofs >/dev/null || skip "macOS needs mkisofs from cdrtools"
  local wanted
  video_ts "${SRC}"
  wanted="$(player_order)"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --dvd-video </dev/null

  # Assert
  local order kinds
  order="$(video_order "${OUT}")"
  kinds="$(descriptors "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${order}" == "${wanted}" ]]
  [[ "${kinds}" == *"udf "* ]]
  [[ "${lines[3]}" == "Video         DVD Video, VIDEO_TS in player order" ]]
}

@test "enban build --dvd-video finds VIDEO_TS among the layout entries" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || command -v mkisofs >/dev/null || skip "macOS needs mkisofs from cdrtools"
  local call wanted
  video_ts "${WORK}/movie"
  call="$(layout_call VIDEO_TS "${WORK}/movie/VIDEO_TS")"
  wanted="$(player_order)"

  # Act
  run disk_test_call eval "DISK_BUILD_DVD=y ${call}"

  # Assert
  local order
  order="$(video_order "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${order}" == "${wanted}" ]]
}

@test "enban build --dvd-video on macOS needs mkisofs for its UDF" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Darwin" ]] || skip "Linux builds DVD Video with genisoimage"
  local farm
  video_ts "${SRC}"
  farm="$(disk_test_farm mkisofs)"

  # Act
  run disk_test_run_path "${farm}" enban build "${SRC}" "${OUT}" --dvd-video </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: UDF on macOS needs mkisofs from cdrtools. install it with brew install cdrtools, or leave udf out of --fs." ]]
}

@test "enban build --dvd-video reports a mkisofs that fails and leaves no image" {
  # Arrange
  video_ts "${SRC}"
  disk_test_shim mkisofs "exit 1"
  disk_test_shim genisoimage "exit 1"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --dvd-video </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to build ${OUT} from ${SRC}." ]]
  [[ ! -e "${OUT}" ]]
}

@test "enban build --dvd-video needs a VIDEO_TS folder at the root" {
  # Arrange
  local option=--dvd-video

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --dvd-video needs a VIDEO_TS folder at the root of the disc." ]]
}

@test "enban build --dvd-video needs UDF" {
  # Arrange
  video_ts "${SRC}"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --dvd-video --fs iso9660,joliet </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --dvd-video needs udf in --fs, since a DVD player reads the disc through UDF." ]]
}

@test "enban build --dvd-video does not boot" {
  # Arrange
  video_ts "${SRC}"
  head -c 2048 /dev/zero >"${WORK}/boot.bin"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --dvd-video --boot "${WORK}/boot.bin" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --dvd-video and --boot do not go together: a DVD Video disc does not boot." ]]
}

bdmv_tree() {
  mkdir -p "$1/BDMV/STREAM" "$1/BDMV/PLAYLIST"
  head -c 1500000 /dev/urandom >"$1/BDMV/STREAM/00000.m2ts"
  head -c 2048 /dev/urandom >"$1/BDMV/index.bdmv"
  : >"$1/BDMV/PLAYLIST/00000.mpls"
}

udf_word() {
  local value
  value="$(od -An -tu4 -j "$2" -N 4 "$1")"
  printf '%s' "${value//[[:space:]]/}"
}

udf_revision() {
  local sequence sector kind revision
  sequence="$(udf_word "$1" $((256 * 2048 + 20)))"
  for sector in $(seq "${sequence}" $((sequence + 15))); do
    kind="$(od -An -tu2 -j $((sector * 2048)) -N 2 "$1")"
    [[ "${kind//[[:space:]]/}" == "6" ]] || continue
    revision="$(od -An -tx2 -j $((sector * 2048 + 240)) -N 2 "$1")"
    printf '%s' "${revision//[[:space:]]/}"
    return 0
  done
  return 1
}

udf_files() {
  case "${ENBAN_TEST_OS}" in
  Darwin) image_files "$1" ;;
  *)
    mkdir -p "${WORK}/mnt"
    sudo mount -o loop,ro -t udf "$1" "${WORK}/mnt" || return 1
    sized_files "${WORK}/mnt"
    sudo umount "${WORK}/mnt"
    ;;
  esac
}

leftovers() {
  find "${WORK}" -maxdepth 1 -name '.enban-build.*'
}

@test "enban build --bdmv writes the folder as UDF 2.50 and nothing else" {
  # Arrange
  local wanted
  bdmv_tree "${SRC}"
  wanted="$(sized_files "${SRC}")"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --bdmv </dev/null

  # Assert
  local listed revision left
  listed="$(udf_files "${OUT}")"
  revision="$(udf_revision "${OUT}")"
  left="$(leftovers)"
  [[ "${status}" -eq 0 ]]
  [[ "${listed}" == "${wanted}" ]]
  [[ "${revision}" == "0250" ]]
  [[ "${lines[2]}" == "File systems  UDF 2.50" ]]
  [[ -z "${left}" ]]
}

@test "enban build --bdmv finds BDMV among the layout entries" {
  # Arrange
  local call wanted
  bdmv_tree "${WORK}/movie"
  call="$(layout_call BDMV "${WORK}/movie/BDMV" notes.txt "${SRC}/notes.txt")"
  cp -f "${SRC}/notes.txt" "${WORK}/movie/notes.txt"
  wanted="$(sized_files "${WORK}/movie")"

  # Act
  run disk_test_call eval "DISK_BUILD_BDMV=y ${call}"

  # Assert
  local listed
  listed="$(udf_files "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${listed}" == "${wanted}" ]]
}

@test "enban build --bdmv needs a BDMV folder at the root" {
  # Arrange
  local option=--bdmv

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --bdmv needs a BDMV folder at the root of the disc." ]]
}

@test "enban build --bdmv takes none of the other build fields" {
  # Arrange
  bdmv_tree "${SRC}"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --bdmv --publisher Franco </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --bdmv writes UDF 2.50 alone, which holds a label and nothing more, so leave out --publisher." ]]
}

@test "enban build --udf-version 1.50 writes UDF 1.50 alone" {
  # Arrange
  local wanted
  wanted="$(sized_files "${SRC}")"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --udf-version 1.50 </dev/null

  # Assert
  local revision listed
  revision="$(udf_revision "${OUT}")"
  listed="$(udf_files "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${revision}" == "0150" ]]
  [[ "${listed}" == "${wanted}" ]]
  [[ "${lines[2]}" == "File systems  UDF 1.50" ]]
}

@test "enban build --udf-version 2.00 writes UDF 2.00 alone" {
  # Arrange
  local version=2.00

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --udf-version "${version}" </dev/null

  # Assert
  local revision
  revision="$(udf_revision "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${revision}" == "0200" ]]
}

@test "enban build --udf-version 2.01 writes UDF 2.01 alone" {
  # Arrange
  local wanted
  wanted="$(sized_files "${SRC}")"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --udf-version 2.01 </dev/null

  # Assert
  local revision listed
  revision="$(udf_revision "${OUT}")"
  listed="$(udf_files "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${revision}" == "0201" ]]
  [[ "${listed}" == "${wanted}" ]]
  [[ "${lines[2]}" == "File systems  UDF 2.01" ]]
}

@test "enban build --udf-version 2.60 keeps a name in another alphabet" {
  # Arrange
  local wanted
  printf 'kana' >"${SRC}/写真.txt"
  wanted="$(sized_files "${SRC}")"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --udf-version 2.60 </dev/null

  # Assert
  local revision listed
  revision="$(udf_revision "${OUT}")"
  listed="$(udf_files "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${revision}" == "0260" ]]
  [[ "${listed}" == "${wanted}" ]]
}

@test "enban build --udf-version 2.60 takes a label and no other field" {
  # Arrange
  local version=2.60

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --udf-version "${version}" --preparer Gustavo </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --udf-version 2.60 writes UDF 2.60 alone, which holds a label and nothing more, so leave out --preparer." ]]
}

@test "a UDF image refuses a name that holds a tab" {
  # Arrange
  printf 'x' >"${SRC}/a${DISK_TEST_TAB:-$'\t'}b.txt"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --udf-version 2.01 </dev/null

  # Assert
  local left
  left="$(leftovers)"
  [[ "${status}" -eq 1 ]]
  [[ "${lines[0]}" == "enban: a UDF image cannot take the name a"$'\t'"b.txt, which holds a tab." ]]
  [[ -z "${left}" ]]
}

@test "a UDF image refuses a name that holds a line break" {
  # Arrange
  printf 'x' >"${SRC}/a"$'\n'"b.txt"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --udf-version 2.01 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: a UDF image cannot take a name that holds a line break, and ${SRC} has one."* ]]
}

@test "a UDF image refuses a character outside Unicode's first plane" {
  # Arrange
  printf 'x' >"${SRC}/smile "$'\360\237\230\200'".txt"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --udf-version 2.01 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[0]}" == "enban: a UDF image cannot take a name with a character outside Unicode's first plane, such as an emoji." ]]
}

@test "a UDF image takes folders and files only" {
  # Arrange
  mkfifo "${SRC}/pipe"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --udf-version 2.01 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[0]}" == "enban: a UDF image takes folders and files, and ${SRC}/pipe is neither." ]]
}

@test "a UDF image reports a copy that fails and leaves nothing behind" {
  # Arrange
  bdmv_tree "${SRC}"
  disk_test_shim dd 'case " $* " in *" if=/dev/zero "*|*" if='"${WORK}"'/.enban-build"*) exec "$REAL" "$@" ;; esac; exit 1'

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --bdmv </dev/null

  # Assert
  local left
  left="$(leftovers)"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to build ${OUT} from ${SRC}." ]]
  [[ -z "${left}" ]]
}

@test "enban build --udf-version 1.02 writes UDF 1.02 beside ISO9660" {
  # Arrange
  local version=1.02

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --udf-version "${version}" </dev/null

  # Assert
  local revision
  revision="$(udf_revision "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${revision}" == "0102" ]]
  [[ "${lines[2]}" == "File systems  ISO9660, Joliet, UDF 1.02" ]]
}

@test "enban build refuses a UDF revision it does not know" {
  # Arrange
  local version=3.00

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --udf-version "${version}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --udf-version takes 1.02, 1.50, 2.00, 2.01, 2.50 or 2.60, got: 3.00" ]]
}

@test "enban build --udf-version needs udf in --fs" {
  # Arrange
  local version=1.02

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --fs iso9660 --udf-version "${version}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --udf-version needs udf in --fs." ]]
}

@test "enban build keeps DVD Video on UDF 1.02" {
  # Arrange
  video_ts "${SRC}"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --dvd-video --udf-version 2.01 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --dvd-video uses UDF 1.02, the revision a DVD player reads." ]]
}

@test "enban build keeps BDMV on UDF 2.50" {
  # Arrange
  bdmv_tree "${SRC}"

  # Act
  run disk_test_run enban build "${SRC}" "${OUT}" --bdmv --udf-version 2.01 </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --bdmv uses UDF 2.50, the revision a Blu-ray player reads." ]]
}

dvd_layer_call() {
  local source out
  source="$(quoted "${SRC}")"
  out="$(quoted "${OUT}")"
  printf 'DISK_LAYER_SINGLE=1 DISK_LAYER_ZERO=%s DISK_BUILD_DVD=y DISK_BUILD_SOURCE=%s DISK_BUILD_OUT=%s; disk_build_run' "$1" "${source}" "${out}"
}

ifo_lba() {
  local report
  report="$(xorriso -indev "$1" -find /VIDEO_TS -type f -name "$2" -exec report_lba -- 2>/dev/null)"
  sed -n "s/^File data lba: *0 , *\([0-9]*\) ,.*/\1/p" <<<"${report}"
}

@test "a dual-layer DVD Video build names its layer break at a cell start" {
  # Arrange
  local call
  video_ts "${SRC}"
  call="$(dvd_layer_call 100000)"

  # Act
  run disk_test_call eval "${call}"

  # Assert
  local ifo
  ifo="$(ifo_lba "${OUT}" VTS_01_0.IFO)"
  [[ "${status}" -eq 0 ]]
  [[ "${lines[4]}" == "Layer break   sector $((ifo + 4)), a cell start in VTS_01" ]]
}

@test "a dual-layer DVD Video build breaks in the middle when no cell starts near it" {
  # Arrange
  local call
  video_ts "${SRC}"
  call="$(dvd_layer_call 2)"

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[4]}" == "Layer break   sector "*", the middle, since no cell starts near it" ]]
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

project() {
  printf '%s\n' "$@" >"${WORK}/family.enban"
}

@test "enban build --project builds the entries and fields the project holds" {
  # Arrange
  local tab=$'\t'
  project enban-project=1 "fs=iso9660" "label=Kyoto trip" "" "entry=pictures${tab}${SRC}/sub" "entry=notes.txt${tab}${SRC}/notes.txt"

  # Act
  run disk_test_run enban build --project "${WORK}/family.enban" "${OUT}" </dev/null

  # Assert
  local listed kinds label
  image_files "${OUT}" >"${WORK}/listed.txt"
  listed="$(tr '[:upper:]' '[:lower:]' <"${WORK}/listed.txt")"
  kinds="$(descriptors "${OUT}")"
  label="$(volume_id "${OUT}")"
  [[ "${status}" -eq 0 ]]
  [[ "${listed}" == *"notes.txt"*"pictures/photo.bin"* ]]
  [[ "${kinds}" == "" ]]
  [[ "${label}" == "KYOTO_TRIP" ]]
}

@test "enban build --project refuses another build option beside it" {
  # Arrange
  project enban-project=1

  # Act
  run disk_test_run enban build --project "${WORK}/family.enban" "${OUT}" --label Trip </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--label' cannot go with --project, which holds the build options. run 'enban help' for usage." ]]
}

@test "enban build --project takes only the image file" {
  # Arrange
  project enban-project=1

  # Act
  run disk_test_run enban build --project "${WORK}/family.enban" "${SRC}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: build --project takes only the image file to create. run 'enban help' for usage." ]]
}

@test "enban build --project needs the image file" {
  # Arrange
  project enban-project=1

  # Act
  run disk_test_run enban build --project "${WORK}/family.enban" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: build --project takes only the image file to create. run 'enban help' for usage." ]]
}

@test "enban build --project says when there is no project at the path" {
  # Arrange
  local missing="${WORK}/missing.enban"

  # Act
  run disk_test_run enban build --project "${missing}" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: there is no project at ${missing}." ]]
}

@test "enban build --project refuses a file that is not a project" {
  # Arrange
  project "fs=iso9660"

  # Act
  run disk_test_run enban build --project "${WORK}/family.enban" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${WORK}/family.enban is not an enban project." ]]
}

@test "enban build --project names a line it does not know" {
  # Arrange
  project enban-project=1 "fs=iso9660" "colour=red"

  # Act
  run disk_test_run enban build --project "${WORK}/family.enban" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${WORK}/family.enban line 3: unknown setting colour." ]]
}

@test "enban build --project needs yes or no for dvd_video and bdmv" {
  # Arrange
  project enban-project=1 "bdmv=maybe"

  # Act
  run disk_test_run enban build --project "${WORK}/family.enban" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${WORK}/family.enban line 2: bdmv must be yes or no, got: maybe" ]]
}

@test "enban build --project needs a name, a tab and a full path in each entry" {
  # Arrange
  project enban-project=1 "entry=notes.txt notes.txt"

  # Act
  run disk_test_run enban build --project "${WORK}/family.enban" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${WORK}/family.enban line 2: an entry is a name, a tab and a full path." ]]
}

@test "enban build --project says when the project holds nothing to build" {
  # Arrange
  project enban-project=1 "dvd_video=no" "bdmv=no"

  # Act
  run disk_test_run enban build --project "${WORK}/family.enban" "${OUT}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${WORK}/family.enban has no files or folders to build." ]]
}

@test "info refuses --project, which only build takes" {
  # Arrange
  project enban-project=1

  # Act
  run disk_test_run enban info --drive "stdio:${OUT}" --project "${WORK}/family.enban" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--project' works only with build. run 'enban help' for usage." ]]
}

@test "a project sets every build field it names" {
  # Arrange
  local tab=$'\t'
  project enban-project=1 "fs=iso9660,udf" "label=Trip" "publisher=Family" "date=20091224180000" "boot=${SRC}/notes.txt" \
    "emulation=floppy" "platform=efi" "dvd_video=yes" "bdmv=no" "udf_version=2.50" "entry=sub${tab}${SRC}/sub"
  local call="disk_project_read '${WORK}/family.enban'; printf '%s|' \"\${DISK_BUILD_FS}\" \"\${DISK_BUILD_LABEL}\" \"\${DISK_BUILD_PUBLISHER}\" \"\${DISK_BUILD_DATE}\" \"\${DISK_BUILD_BOOT}\" \"\${DISK_BUILD_EMULATION}\" \"\${DISK_BUILD_PLATFORM}\" \"\${DISK_BUILD_DVD}\" \"\${DISK_BUILD_BDMV}\" \"\${DISK_BUILD_UDF_VERSION}\""

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "iso9660,udf|Trip|Family|20091224180000|${SRC}/notes.txt|floppy|efi|y|n|2.50|" ]]
}

@test "saving a project leaves nothing behind when no backup name is free" {
  # Arrange
  local count=1
  printf 'older\n' >"${WORK}/trip.enban"
  printf 'older\n' >"${WORK}/trip.enban.bak"
  while [[ "${count}" -le 99 ]]; do
    printf 'older\n' >"${WORK}/trip.enban.bak.${count}"
    count=$((count + 1))
  done
  local tab=$'\t'
  local call="DISK_BUILD_LAYOUT='notes.txt${tab}${SRC}/notes.txt'; disk_project_save '${WORK}/trip.enban'"

  # Act
  run disk_test_call eval "${call}"

  # Assert
  local left
  left="$(find "${WORK}" -name '.enban-project.*')"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${WORK}/trip.enban.bak to .bak.99 all exist, so there is no room to keep ${WORK}/trip.enban." ]]
  [[ -z "${left}" ]]
  [[ "$(<"${WORK}/trip.enban")" == "older" ]]
}
