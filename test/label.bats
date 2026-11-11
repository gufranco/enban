#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-label.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  SRC="${WORK}/files"
  IMAGE="${WORK}/disc.iso"
  mkdir -p "${SRC}"
  printf 'hello\n' >"${SRC}/a.txt"
}

teardown() {
  rm -rf "${WORK}"
}

image_with() {
  disk_test_run enban build "${SRC}" "${IMAGE}" --label OLD --fs "$1" </dev/null >/dev/null
}

primary_label() {
  dd if="${IMAGE}" bs=1 skip=$((16 * 2048 + 40)) count=32 2>/dev/null
}

joliet_label() {
  dd if="${IMAGE}" of="${WORK}/joliet.bin" bs=1 skip=$((17 * 2048 + 40)) count=32 2>/dev/null
  iconv -f UTF-16BE -t UTF-8 "${WORK}/joliet.bin"
}

@test "enban label renames the ISO 9660 and Joliet labels in place" {
  # Arrange
  image_with iso9660,joliet

  # Act
  run disk_test_run enban label "${IMAGE}" "Trip to Kyoto" </dev/null

  # Assert
  local primary joliet
  primary="$(primary_label)"
  joliet="$(joliet_label)"
  [[ "${status}" -eq 0 ]]
  [[ "${primary}" == "TRIP_TO_KYOTO                   " ]]
  [[ "${joliet}" == "Trip to Kyoto   " ]]
  [[ "${output}" == "Done. ${IMAGE} is labelled TRIP_TO_KYOTO, Trip to Kyoto on Joliet. The original is kept as ${IMAGE}.bak." ]]
}

@test "enban label keeps the first 16 characters on Joliet" {
  # Arrange
  image_with iso9660,joliet

  # Act
  run disk_test_run enban label "${IMAGE}" "Summer holidays 2024 in Kyoto" </dev/null

  # Assert
  local joliet
  joliet="$(joliet_label)"
  [[ "${status}" -eq 0 ]]
  [[ "${joliet}" == "Summer holidays " ]]
}

@test "enban label changes only ISO 9660 when the image has no Joliet" {
  # Arrange
  image_with iso9660

  # Act
  run disk_test_run enban label "${IMAGE}" backup </dev/null

  # Assert
  local primary
  primary="$(primary_label)"
  [[ "${status}" -eq 0 ]]
  [[ "${primary}" == "BACKUP                          " ]]
  [[ "${output}" == "Done. ${IMAGE} is labelled BACKUP. The original is kept as ${IMAGE}.bak." ]]
}

@test "enban label renames UDF as well" {
  # Arrange
  image_with iso9660,joliet,udf

  # Act
  run disk_test_run enban label "${IMAGE}" "Trip to Kyoto" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "Done. ${IMAGE} is labelled TRIP_TO_KYOTO, Trip to Kyoto on Joliet, Trip to Kyoto on UDF. The original is kept as ${IMAGE}.bak." ]]
}

@test "enban label leaves UDF that udftools reads as the new label with sound checksums" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "udfinfo, the independent UDF checker, exists on Linux only"
  image_with iso9660,joliet,udf

  # Act
  run disk_test_run enban label "${IMAGE}" "Trip to Kyoto" </dev/null

  # Assert
  local label volume
  udfinfo "${IMAGE}" >"${WORK}/udf.txt" 2>/dev/null
  label="$(sed -n 's/^label=//p' "${WORK}/udf.txt")"
  volume="$(sed -n 's/^vid=//p' "${WORK}/udf.txt")"
  [[ "${status}" -eq 0 ]]
  [[ "${label}" == "Trip to Kyoto" ]]
  [[ "${volume}" == "Trip to Kyoto" ]]
  udflabel --force "${IMAGE}" "Checked" >/dev/null 2>&1
}

@test "enban label keeps 30 characters of the UDF volume ID" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "udfinfo, the independent UDF checker, exists on Linux only"
  image_with iso9660,udf

  # Act
  run disk_test_run enban label "${IMAGE}" "Summer holidays 2024 in Kyoto!!" </dev/null

  # Assert
  local volume
  udfinfo "${IMAGE}" >"${WORK}/udf.txt" 2>/dev/null
  volume="$(sed -n 's/^vid=//p' "${WORK}/udf.txt")"
  [[ "${status}" -eq 0 ]]
  [[ "${volume}" == "Summer holidays 2024 in Kyoto!" ]]
}

@test "enban label warns when UDF has no anchor" {
  # Arrange
  image_with iso9660
  printf '\000NSR02\001' | dd of="${IMAGE}" bs=1 seek=$((18 * 2048)) conv=notrunc 2>/dev/null

  # Act
  run disk_test_run enban label "${IMAGE}" backup </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "enban: warning: ${IMAGE} has UDF with no anchor at sector 256, so its UDF label is unchanged." ]]
}

@test "enban label says when the UDF checksums cannot be computed" {
  # Arrange
  image_with iso9660,udf
  cp "${IMAGE}" "${WORK}/original.iso"
  disk_test_shim awk "case \"\$*\" in *bits_xor*) exit 2 ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"

  # Act
  run disk_test_run enban label "${IMAGE}" backup </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the UDF checksums of ${IMAGE} could not be computed, so the image is restored as it was." ]]
  cmp -s "${WORK}/original.iso" "${IMAGE}"
  [[ ! -e "${IMAGE}.bak" ]]
}

@test "enban label keeps the original image as a backup" {
  # Arrange
  image_with iso9660,joliet
  cp "${IMAGE}" "${WORK}/original.iso"

  # Act
  run disk_test_run enban label "${IMAGE}" backup </dev/null

  # Assert
  local changed=0
  cmp -s "${IMAGE}" "${IMAGE}.bak" || changed=1
  [[ "${status}" -eq 0 ]]
  cmp -s "${WORK}/original.iso" "${IMAGE}.bak"
  [[ "${changed}" -eq 1 ]]
}

@test "enban label never overwrites an earlier backup" {
  # Arrange
  image_with iso9660
  printf 'older\n' >"${IMAGE}.bak"

  # Act
  run disk_test_run enban label "${IMAGE}" backup </dev/null

  # Assert
  local older
  older="$(cat "${IMAGE}.bak")"
  [[ "${status}" -eq 0 ]]
  [[ "${older}" == "older" ]]
  [[ "${output}" == *"The original is kept as ${IMAGE}.bak.1." ]]
}

@test "enban label stops when a hundred backups already exist" {
  # Arrange
  image_with iso9660
  cp "${IMAGE}" "${WORK}/original.iso"
  local count=1
  : >"${IMAGE}.bak"
  while [[ "${count}" -lt 100 ]]; do
    : >"${IMAGE}.bak.${count}"
    count=$((count + 1))
  done

  # Act
  run disk_test_run enban label "${IMAGE}" backup </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${IMAGE}.bak to .bak.99 all exist, so there is no room for a backup. nothing was changed." ]]
  cmp -s "${WORK}/original.iso" "${IMAGE}"
}

@test "enban label changes nothing when the backup cannot be written" {
  # Arrange
  local user
  user="$(id -u)"
  [[ "${user}" != 0 ]] || skip "root writes into a read-only folder"
  image_with iso9660
  cp "${IMAGE}" "${WORK}/original.iso"
  chmod 555 "${WORK}"

  # Act
  run disk_test_run enban label "${IMAGE}" backup </dev/null

  # Assert
  chmod 755 "${WORK}"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to back up ${IMAGE} to ${IMAGE}.bak, so nothing was changed." ]]
  cmp -s "${WORK}/original.iso" "${IMAGE}"
}

@test "enban label is read back by xorriso as the new volume ID" {
  # Arrange
  image_with iso9660,joliet

  # Act
  run disk_test_run enban label "${IMAGE}" archive </dev/null

  # Assert
  local volume
  xorriso -indev "${IMAGE}" -pvd_info >"${WORK}/pvd.txt" 2>/dev/null
  volume="$(sed -n 's/^Volume Id    : //p' "${WORK}/pvd.txt")"
  [[ "${status}" -eq 0 ]]
  [[ "${volume}" == "ARCHIVE" ]]
}

@test "enban label steps over the boot record of a bootable image" {
  # Arrange
  local search_path
  head -c 2048 /dev/zero >"${SRC}/boot.img"
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as mkisofs -quiet -J -b boot.img -no-emul-boot -o "${IMAGE}" "${SRC}" 2>/dev/null

  # Act
  run disk_test_run enban label "${IMAGE}" rescue </dev/null

  # Assert
  local primary
  primary="$(primary_label)"
  [[ "${status}" -eq 0 ]]
  [[ "${primary}" == "RESCUE                          " ]]
  [[ "${output}" == "Done. ${IMAGE} is labelled RESCUE, rescue on Joliet. The original is kept as ${IMAGE}.bak." ]]
}

@test "enban label refuses a file that is not an ISO image" {
  # Arrange
  head -c 65536 /dev/zero >"${IMAGE}"

  # Act
  run disk_test_run enban label "${IMAGE}" backup </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${IMAGE} is not an ISO image, so it has no volume label to change." ]]
}

@test "enban label refuses characters Joliet cannot hold" {
  # Arrange
  image_with iso9660,joliet

  # Act
  run disk_test_run enban label "${IMAGE}" "a/b" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == 'enban: the label takes plain ASCII characters other than * / : ; ? and \, got: a/b' ]]
}

@test "enban label takes up to 32 characters" {
  # Arrange
  image_with iso9660

  # Act
  run disk_test_run enban label "${IMAGE}" "abcdefghijklmnopqrstuvwxyz0123456" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the label takes up to 32 characters, got 33." ]]
}

@test "enban label says when the image is missing" {
  # Arrange
  local gone="${WORK}/gone.iso"

  # Act
  run disk_test_run enban label "${gone}" backup </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no image at ${gone}." ]]
}

@test "enban label needs an image and a label" {
  # Arrange
  local command=label

  # Act
  run disk_test_run enban "${command}" "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: label needs an image and the new label. run 'enban help' for usage." ]]
}
