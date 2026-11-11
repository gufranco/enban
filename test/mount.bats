#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-mount.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  IMAGE="${WORK}/disc.iso"
  mkdir -p "${WORK}/files"
  printf 'hello\n' >"${WORK}/files/a.txt"
  disk_test_run enban build "${WORK}/files" "${IMAGE}" --label MOUNTED --fs iso9660 </dev/null >/dev/null
  [[ "${ENBAN_TEST_OS}" == "Darwin" ]] || disk_test_shim udisksctl "exec sh $(printf '%q' "${ENBAN_TESTS_DIR}/udisksctl.sh") $(printf '%q' "${WORK}") \"\$@\""
}

teardown() {
  local point
  point="$(cat "${WORK}/point" 2>/dev/null || true)"
  if [[ -n "${point}" && -d "${point}" ]]; then
    disk_test_run enban unmount "${point}" </dev/null >/dev/null 2>&1 || true
  fi
  rm -rf "${WORK}"
}

mounted_at() {
  sed -n 's/^Done\. .* is mounted read-only at \(.*\)\.$/\1/p' <<<"$1"
}

@test "enban mount attaches an image read-only and unmount detaches it" {
  # Arrange
  local point

  # Act
  run disk_test_run enban mount "${IMAGE}" </dev/null

  # Assert
  point="$(mounted_at "${output}")"
  printf '%s' "${point}" >"${WORK}/point"
  local content written=0
  content="$(cat "${point}/a.txt" 2>/dev/null || cat "${point}/A.TXT")"
  touch "${point}/new" 2>/dev/null || written=1
  [[ "${status}" -eq 0 ]]
  [[ "${content}" == "hello" ]]
  [[ "${written}" -eq 1 ]]
}

@test "enban unmount detaches what mount attached" {
  # Arrange
  local point mounted
  mounted="$(disk_test_run enban mount "${IMAGE}" </dev/null)"
  point="$(mounted_at "${mounted}")"
  printf '%s' "${point}" >"${WORK}/point"

  # Act
  run disk_test_run enban unmount "${point}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "Done. ${point} is unmounted." ]]
  [[ ! -e "${point}/a.txt" ]]
}

@test "enban mount says when the image cannot be mounted" {
  # Arrange
  head -c 65536 /dev/zero >"${WORK}/blank.img"

  # Act
  run disk_test_run enban mount "${WORK}/blank.img" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to mount ${WORK}/blank.img." ]]
}

@test "enban unmount says when nothing is mounted there" {
  # Arrange
  mkdir -p "${WORK}/empty"

  # Act
  run disk_test_run enban unmount "${WORK}/empty" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unable to unmount ${WORK}/empty. close what uses it and try again." ]]
}

@test "enban unmount says when the folder is missing" {
  # Arrange
  local gone="${WORK}/gone"

  # Act
  run disk_test_run enban unmount "${gone}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no folder at ${gone}." ]]
}

@test "enban mount says when the image is missing" {
  # Arrange
  local gone="${WORK}/gone.iso"

  # Act
  run disk_test_run enban mount "${gone}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no image at ${gone}." ]]
}

@test "enban mount on Linux needs udisksctl" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS always has hdiutil"
  local farm
  farm="$(disk_test_farm udisksctl)"

  # Act
  run disk_test_run_path "${farm}" enban mount "${IMAGE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: mount needs udisksctl. install udisks2 and try again." ]]
}

@test "enban mount and unmount need a path" {
  # Arrange
  local command=mount

  # Act
  run disk_test_run enban "${command}" </dev/null

  # Assert
  local unmount
  unmount="$(disk_test_run enban unmount </dev/null 2>&1 || true)"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: mount needs an image. run 'enban help' for usage." ]]
  [[ "${unmount}" == "enban: unmount needs the folder the image is mounted at. run 'enban help' for usage." ]]
}
