#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-ttab.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_TEST_GUM APP_PATH
  IMAGE="${WORK}/image.iso"
  DISC="${WORK}/disc.iso"
  dd if=/dev/urandom of="${IMAGE}" bs=2048 count=64 2>/dev/null
  : >"${DISC}"
  export ENBAN_TEST_GUM_ANSWERS="${WORK}/answers"
  disk_test_shim stty "case \"\$1\" in size) printf '50 200\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
}

teardown() {
  rm -rf "${WORK}"
}

linux_only() {
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
}

answers() {
  printf '%s\n' "$@" >"${ENBAN_TEST_GUM_ANSWERS}"
}

written() {
  local search_path
  disk_test_drive "$1" "$2" 2298496 22160
  search_path="$(disk_test_path)"
  PATH="${search_path}" xorriso -as cdrecord dev="stdio:${DISC}" -dao "${IMAGE}" >/dev/null 2>&1
}

@test "the Tools tab lists the drive and image tools with the focus on Erase disc" {
  # Arrange
  local keys='7q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Drive"*"> Erase disc"*"Close"*"Capabilities"*"Image"*"Checksum"*"Mount"* ]]
}

@test "a tool still to come says which part of enban brings it" {
  # Arrange
  local keys='7\033[B\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Close"* ]]
  [[ "${shown}" == *"Close arrives with the raw SCSI tools."* ]]
}

@test "the focus stops at both ends of the tool list" {
  # Arrange
  local keys
  keys="7\\033[A$(printf '\\033[B%.0s' {1..20})q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Mount"* ]]
}

@test "Enter on Erase disc opens the erase panel and space picks the method" {
  # Arrange
  local keys='7\n q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Erase disc"*"Method     full"* ]]
  [[ "${shown}" == *"Everything on the disc is lost."* ]]
}

@test "Escape leaves the erase panel for the tool list" {
  # Arrange
  local keys='7\n\033[Zq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Erase disc"*"quick or full"* ]]
}

@test "the erase panel needs a drive" {
  # Arrange
  local keys='7\n\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to erase."* ]]
}

@test "the erase panel erases a rewritable disc after the drive's name" {
  # Arrange
  linux_only
  written 0013 "DVD-RW restricted overwrite"
  answers disc.iso

  # Act
  run on_terminal_in_steps '7\n\n' 'is erased' 'q' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Result"*"Done. stdio:${DISC} is erased."* ]]
}

@test "the erase panel touches nothing without the drive's name" {
  # Arrange
  linux_only
  written 0013 "DVD-RW restricted overwrite"
  cp "${DISC}" "${WORK}/before.iso"
  answers wrong

  # Act
  run on_terminal '7\n\nq' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Nothing was erased."* ]]
  cmp -s "${WORK}/before.iso" "${DISC}"
}

@test "the erase panel shows why a disc cannot be erased" {
  # Arrange
  linux_only
  written 0011 "DVD-R sequential recording"
  answers disc.iso

  # Act
  run on_terminal_in_steps '7\n\n' 'the result says why' 'q' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"is a DVD-R, which cannot be erased."* ]]
}

@test "c cancels an erase" {
  # Arrange
  linux_only
  written 0013 "DVD-RW restricted overwrite"
  disk_test_drive_flag slow
  answers disc.iso

  # Act
  run on_terminal_in_steps '7\n\n' 'Press c to cancel' 'cq' --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Cancelled while erasing. The disc may be unusable."* ]]
}

@test "c cancels a checksum" {
  # Arrange
  disk_test_shim shasum "sleep 43; exec \"\${REAL}\" \"\$@\""
  disk_test_shim sha256sum "sleep 43; exec \"\${REAL}\" \"\$@\""
  answers "${IMAGE}"

  # Act
  run on_terminal_in_steps "7$(printf '\\033[B%.0s' {1..12})\\n" 'Press c to cancel' 'cq'

  # Assert
  local shown left
  shown="$(last_frame)"
  left="$(pgrep -f 'sleep 43' || true)"
  [[ "${shown}" == *"Cancelled while checking. Nothing changed."* ]]
  [[ -z "${left}" ]]
}

@test "Tray ejects the disc" {
  # Arrange
  linux_only
  written 0011 "DVD-R sequential recording"

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..4})\\nq" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"The tray of stdio:${DISC} is open."* ]]
}

@test "Tray says when the tray did not open" {
  # Arrange
  linux_only
  written 0011 "DVD-R sequential recording"
  disk_test_drive_flag fail_eject

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..4})\\nq" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"The tray of stdio:${DISC} did not open."* ]]
}

@test "Tray needs a drive" {
  # Arrange
  local keys
  keys="7$(printf '\\033[B%.0s' {1..4})\\nq"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to eject."* ]]
}

@test "Capabilities lists the kinds of disc the drive handles" {
  # Arrange
  linux_only
  written 0011 "DVD-R sequential recording"
  disk_test_drive_profiles 0011 0009 000a 0011 001a

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..5})\\nq" --drive "stdio:${DISC}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Capabilities"*"CD-R"*"CD-RW"*"DVD-R"*"DVD+RW"* ]]
}

@test "Capabilities says when no drive is chosen and Enter goes back" {
  # Arrange
  local keys
  keys="7$(printf '\\033[B%.0s' {1..5})\\n"

  # Act
  run on_terminal_in_steps "${keys}" 'The drive reports nothing' '\nq'

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"The drive reports nothing it can read or write."* ]]
  [[ "${final}" == *"> Capabilities"* ]]
}

@test "Checksum prints the checksums of the chosen image" {
  # Arrange
  local line
  line="$(openssl dgst -sha256 "${IMAGE}")"
  answers "${IMAGE}"

  # Act
  run on_terminal_in_steps "7$(printf '\\033[B%.0s' {1..12})\\n" 'is checked' 'q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Result"*"SHA-256  ${line##* }"* ]]
}

@test "Checksum of the disc needs a drive" {
  # Arrange
  answers ""

  # Act
  run on_terminal "7$(printf '\\033[B%.0s' {1..12})\\nq"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to check."* ]]
}

@test "the Tools tab starts nothing while a read runs" {
  # Arrange
  local call='DISK_APP_JOB=running DISK_APP_JOB_KIND=read DISK_APP_JOB_PID=1; disk_tools_tab_erase; printf "%s|%s|%s\n" "${DISK_APP_JOB_KIND}" "${DISK_APP_JOB_PID}" "${DISK_APP_STATUS}"'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "read|1|A read is running. Press c on its tab to cancel it first." ]]
}

@test "the Tools tab ignores other keys" {
  # Arrange
  local keys='7zq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Erase disc"* ]]
}
