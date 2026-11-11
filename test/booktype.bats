#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-book.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  DISC="${WORK}/disc.iso"
  DRIVE="stdio:${DISC}"
  : >"${DISC}"
}

teardown() {
  rm -rf "${WORK}"
}

linux_only() {
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
}

as_root() {
  disk_test_shim id "case \"\$1\" in -u) printf '0\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
}

booktype_tool() {
  disk_test_shim dvd+rw-booktype "printf '%s\\n' \"\$*\" >>'${WORK}/booktype.log'; [ \"\$1\" != -inq ] || printf 'Book type: DVD+R\\n'; [ ! -e '${WORK}/booktype.fail' ] || { printf ':-( unable to set book type\\n' >&2; exit 1; }"
}

@test "enban booktype makes a DVD+R read as DVD-ROM after the drive's name" {
  # Arrange
  linux_only
  disk_test_drive 001b "DVD+R" 2298496 22160
  as_root
  booktype_tool

  # Act
  run disk_test_run enban booktype --drive "${DRIVE}" dvd-rom <<<"disc.iso"

  # Assert
  local sent
  sent="$(cat "${WORK}/booktype.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "-dvd-rom-spec -media ${DISC}" ]]
  [[ "${output}" == *"Done. the disc in ${DRIVE} reads as DVD-ROM." ]]
}

@test "enban booktype shows the book type when none is asked for" {
  # Arrange
  linux_only
  disk_test_drive 001a "DVD+RW" 2298496 22160
  as_root
  booktype_tool

  # Act
  run disk_test_run enban booktype --drive "${DRIVE}" </dev/null

  # Assert
  local sent
  sent="$(cat "${WORK}/booktype.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "-inq ${DISC}" ]]
  [[ "${output}" == "Book type: DVD+R" ]]
}

@test "enban booktype changes nothing without the drive's name" {
  # Arrange
  linux_only
  disk_test_drive 001b "DVD+R" 2298496 22160
  as_root
  booktype_tool

  # Act
  run disk_test_run enban booktype --drive "${DRIVE}" dvd+r <<<"wrong"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: cancelled, nothing was touched." ]]
  [[ ! -e "${WORK}/booktype.log" ]]
}

@test "enban booktype says why the tool failed" {
  # Arrange
  linux_only
  disk_test_drive 002b "DVD+R/DL" 2298496 22160
  as_root
  booktype_tool
  : >"${WORK}/booktype.fail"

  # Act
  run disk_test_run enban booktype --drive "${DRIVE}" dvd+rw <<<"disc.iso"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: the book type did not change: :-( unable to set book type" ]]
}

@test "enban booktype refuses a disc other than DVD+R or DVD+RW" {
  # Arrange
  linux_only
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160
  as_root
  booktype_tool

  # Act
  run disk_test_run enban booktype --drive "${DRIVE}" dvd-rom </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: the book type applies to DVD+R and DVD+RW discs, and the disc in ${DRIVE} is a DVD-R." ]]
}

@test "enban booktype needs root" {
  # Arrange
  linux_only
  disk_test_drive 001b "DVD+R" 2298496 22160
  disk_test_shim id "printf '1000\\n'"
  booktype_tool

  # Act
  run disk_test_run enban booktype --drive "${DRIVE}" dvd-rom </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the book type needs root. run the same command again with sudo." ]]
}

@test "enban booktype needs dvd+rw-booktype" {
  # Arrange
  linux_only
  disk_test_drive 001b "DVD+R" 2298496 22160
  local farm
  farm="$(disk_test_farm dvd+rw-booktype)"

  # Act
  run disk_test_run_path "${farm}" enban booktype --drive "${DRIVE}" dvd-rom </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: booktype needs dvd+rw-booktype from dvd+rw-tools. install it and try again." ]]
}

@test "enban booktype refuses a type it does not know" {
  # Arrange
  local kind=hd-dvd

  # Act
  run disk_test_run enban booktype --drive "${DRIVE}" "${kind}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the book type must be dvd-rom, dvd+r or dvd+rw, got: hd-dvd" ]]
}

@test "enban booktype needs --drive" {
  # Arrange
  local command=booktype

  # Act
  run disk_test_run enban "${command}" dvd-rom </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: booktype needs --drive. run 'enban help' for usage." ]]
}

@test "enban booktype makes a disc read as DVD+R and draws its result with gum" {
  # Arrange
  linux_only
  disk_test_drive 001a "DVD+RW" 2298496 22160
  as_root
  booktype_tool
  export ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log"

  # Act
  run disk_test_run enban booktype --drive "${DRIVE}" dvd+r <<<"disc.iso"

  # Assert
  local sent
  sent="$(cat "${WORK}/booktype.log")"
  [[ "${status}" -eq 0 ]]
  [[ "${sent}" == "-dvd+r-spec -media ${DISC}" ]]
  grep -qF -- "Done. the disc in ${DRIVE} reads as DVD+R." "${WORK}/gum.log"
}
