#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-btab.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_TEST_GUM APP_PATH
  SRC="${WORK}/photos"
  OUT="${WORK}/out.iso"
  mkdir -p "${SRC}/trip"
  head -c 3000 /dev/urandom >"${SRC}/trip/kyoto-temple.jpg"
  head -c 900 /dev/urandom >"${WORK}/notes.txt"
  export ENBAN_TEST_GUM_ANSWERS="${WORK}/answers"
  disk_test_shim stty "case \"\$1\" in size) printf '50 200\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
}

teardown() {
  rm -rf "${WORK}"
}

disc_files() {
  if [[ "${ENBAN_TEST_OS}" == "Darwin" ]]; then
    mkdir -p "${WORK}/mnt"
    hdiutil attach -readonly -nobrowse -mountpoint "${WORK}/mnt" "$1" >/dev/null || return 1
    (cd "${WORK}/mnt" && find . -type f | sed 's|^\.||')
    hdiutil detach "${WORK}/mnt" >/dev/null 2>&1 || hdiutil detach -force "${WORK}/mnt" >/dev/null
    return 0
  fi
  xorriso -indev "$1" -find / -type f 2>/dev/null
}

answers() {
  printf '%s\n' "$@" >"${ENBAN_TEST_GUM_ANSWERS}"
}

@test "f adds a folder to the disc layout and a adds a file" {
  # Arrange
  answers "${SRC}" "${WORK}/notes.txt"

  # Act
  run on_terminal '3faq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"/  "*"2 files, 2 folders"* ]]
  [[ "${shown}" == *"photos/"*"folder"* ]]
  [[ "${shown}" == *"notes.txt"*"file"* ]]
  [[ "${shown}" == *"Added notes.txt"* ]]
}

@test "the Build tab says when the folder or file to add is not there" {
  # Arrange
  answers "${WORK}/nowhere" "${SRC}"

  # Act
  run on_terminal_in_steps '3f' 'No folder at' 'aq'

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"No folder at ${WORK}/nowhere."* ]]
  [[ "${final}" == *"No file at ${SRC}."* ]]
}

@test "the Build tab refuses a second entry with the same name" {
  # Arrange
  answers "${SRC}" "${SRC}"

  # Act
  run on_terminal '3ffq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"photos is already on the disc. Rename it first with n."* ]]
}

@test "x removes the focused entry" {
  # Arrange
  answers "${SRC}" "${WORK}/notes.txt"

  # Act
  run on_terminal '3faxq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Removed notes.txt."* ]]
  [[ "${shown}" != *"notes.txt  "*"file"* ]]
  [[ "${shown}" == *"photos/"* ]]
}

@test "n renames the focused entry on the disc" {
  # Arrange
  answers "${SRC}" "Family 2009"

  # Act
  run on_terminal '3fnq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Family 2009/"* ]]
  [[ "${shown}" == *"Label        FAMILY_2009"* ]]
}

@test "n refuses a name with a slash" {
  # Arrange
  answers "${SRC}" "a/b"

  # Act
  run on_terminal '3fnq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"A name on the disc cannot hold a slash."* ]]
  [[ "${shown}" == *"> photos/"* ]]
}

@test "x and n do nothing when the focus is on a field" {
  # Arrange
  local keys='3xnq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Nothing yet. Press a to add a file or f to add a folder."* ]]
  [[ "${shown}" == *"> Type       ISO9660, Joliet, UDF"* ]]
}

@test "Enter on Type steps through the file system choices" {
  # Arrange
  local keys='3\n\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Type       ISO9660, UDF"* ]]
  [[ "${shown}" == *"Type         ISO9660, UDF"* ]]
}

@test "Enter on Type comes back to all three after ISO9660 alone" {
  # Arrange
  local keys='3\n\n\n\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Type       ISO9660, Joliet, UDF"* ]]
}

@test "Enter on Label names the volume and refuses more than 32 characters" {
  # Arrange
  local long
  long="$(printf 'x%.0s' {1..33})"
  answers "Trip 2024" "${long}"

  # Act
  run on_terminal '3\033[B\n\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Label      Trip 2024"* ]]
  [[ "${shown}" == *"The label takes up to 32 characters."* ]]
}

@test "Enter on Image picks the file to create and refuses one that exists" {
  # Arrange
  answers "${WORK}/notes.txt" "${OUT}"

  # Act
  run on_terminal '3\033[B\033[B\n\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Image      ${OUT}"* ]]
  [[ "${shown}" == *"Ready to build into ${OUT}. Press b to build."* ]]
}

@test "Enter on Image refuses a file that exists" {
  # Arrange
  answers "${WORK}/notes.txt"

  # Act
  run on_terminal '3\033[B\033[B\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"${WORK}/notes.txt already exists. Choose a new name."* ]]
}

@test "b asks for an entry and an image before it builds" {
  # Arrange
  answers "${SRC}"

  # Act
  run on_terminal_in_steps '3b' 'Add a file or folder first' 'fbq'

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"Add a file or folder first: press a or f."* ]]
  [[ "${final}" == *"Choose an image file first: Enter on Image."* ]]
}

@test "b builds the layout into the image and shows the result" {
  # Arrange
  answers "${SRC}" "${OUT}"

  # Act
  run on_terminal_in_steps '3f\033[B\033[B\033[B\nb' 'is built from' 'q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"Result"*"Files         1"*"Done. ${OUT} is built from 1 entry."* ]]
  [[ -s "${OUT}" ]]
}

@test "c cancels a build and leaves no partial image behind" {
  # Arrange
  disk_test_shim hdiutil "sleep 41"
  disk_test_shim genisoimage "sleep 41"
  answers "${SRC}" "${OUT}" y

  # Act
  run on_terminal_in_steps '3f\033[B\033[B\033[B\nb' 'Press c to cancel' 'cq'

  # Assert
  local shown left parts
  shown="$(last_frame)"
  left="$(pgrep -f 'sleep 41' || true)"
  parts="$(find "${WORK}" -maxdepth 1 -name '.enban-build.*')"
  [[ "${shown}" == *"Cancelled while building. No image was written."* ]]
  [[ -z "${left}" ]]
  [[ -z "${parts}" ]]
  [[ ! -e "${OUT}" ]]
}

@test "the Build pane flags names ISO9660 level 1 cannot hold" {
  # Arrange
  answers "${SRC}" "${WORK}/notes.txt"

  # Act
  run on_terminal '3faq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"warn"*"1 name is too long for ISO9660 level 1"* ]]
  [[ "${shown}" == *"ok"*"fits on DVD-R"* ]]
  [[ "${shown}" == *"Content      data"* ]]
}

@test "the Build pane recognises a DVD Video layout" {
  # Arrange
  mkdir -p "${WORK}/VIDEO_TS"
  head -c 100 /dev/urandom >"${WORK}/VIDEO_TS/VIDEO_TS.IFO"
  answers "${WORK}/VIDEO_TS"

  # Act
  run on_terminal '3fq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Content      DVD Video"* ]]
  [[ "${shown}" == *"every name fits ISO9660 level 1"* ]]
}

@test "the Build pane says a layout that is too large for the disc" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 1 22160
  : >"${WORK}/disc.iso"
  answers "${SRC}"

  # Act
  run on_terminal '3fq' --drive "stdio:${WORK}/disc.iso"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"error"*"too large for DVD-R"* ]]
}

@test "the Build tab starts nothing while a write runs" {
  # Arrange
  local call='DISK_APP_JOB=running DISK_APP_JOB_KIND=write DISK_APP_JOB_PID=1; disk_build_tab_start; printf "%s|%s|%s\n" "${DISK_APP_JOB_KIND}" "${DISK_APP_JOB_PID}" "${DISK_APP_STATUS}"'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "write|1|A write is running. Press c on its tab to cancel it first." ]]
}

@test "the Build tab ignores other keys" {
  # Arrange
  local keys='3zq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Disc layout"* ]]
}

@test "Enter on Target switches between an image file and the disc in the drive" {
  # Arrange
  local keys='3\033[B\033[B\033[B\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Target     the disc in the drive"* ]]
}

@test "b to the disc needs a drive" {
  # Arrange
  answers "${SRC}"

  # Act
  run on_terminal '3f\033[B\033[B\033[B\033[B\nbq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"There is no drive to write to."* ]]
}

@test "b to the disc writes nothing without the typed drive name" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  : >"${WORK}/disc.iso"
  answers "${SRC}" "wrong"

  # Act
  run on_terminal '3f\033[B\033[B\033[B\033[B\nbq' --drive "stdio:${WORK}/disc.iso"

  # Assert
  local shown size
  shown="$(last_frame)"
  size="$(wc -c <"${WORK}/disc.iso")"
  [[ "${shown}" == *"Nothing was written."* ]]
  [[ "${size//[[:space:]]/}" -eq 0 ]]
}

@test "b to the disc builds the layout and burns it after the typed drive name" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  : >"${WORK}/disc.iso"
  answers "${SRC}" disc.iso

  # Act
  run on_terminal_in_steps '3f\033[B\033[B\033[B\033[B\nb' 'is written, verified' 'q' --drive "stdio:${WORK}/disc.iso"

  # Assert
  local shown listed
  shown="$(last_frame)"
  listed="$(disc_files "${WORK}/disc.iso")"
  [[ "${shown}" == *"Result"*"Done. stdio:${WORK}/disc.iso is written, verified and ejected."* ]]
  [[ "${listed}" == *"/photos/trip/kyoto-temple.jpg"* ]]
}

@test "b to the disc follows the write defaults of the settings file" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  : >"${WORK}/disc.iso"
  answers "${SRC}" disc.iso
  export ENBAN_CONFIG="${WORK}/config"
  mkdir -p "${ENBAN_CONFIG}"
  printf 'write_eject=no\n' >"${ENBAN_CONFIG}/settings"

  # Act
  run on_terminal_in_steps '3f\033[B\033[B\033[B\033[B\nb' 'is written and verified' 'q' --drive "stdio:${WORK}/disc.iso"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Done. stdio:${WORK}/disc.iso is written and verified."* ]]
}

@test "the Target field shows the drive it writes to" {
  # Arrange
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  : >"${WORK}/disc.iso"

  # Act
  run on_terminal '3\033[B\033[B\033[B\nq' --drive "stdio:${WORK}/disc.iso"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Target     the disc in stdio:${WORK}/disc.iso"* ]]
}

@test "Enter on Publisher names who publishes the disc" {
  # Arrange
  answers "Franco Family"

  # Act
  run on_terminal '3\033[B\033[B\033[B\033[B\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Publisher  Franco Family"* ]]
}

@test "Enter on Date takes YYYYMMDDhhmmss and refuses anything else" {
  # Arrange
  answers 20091224180000 "Christmas 2009"

  # Act
  run on_terminal '3\033[B\033[B\033[B\033[B\033[B\n\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Date       20091224180000"* ]]
  [[ "${shown}" == *"The date must be YYYYMMDDhhmmss, such as 20091224180000."* ]]
}

@test "b records the publisher in the image it builds" {
  # Arrange
  answers "${SRC}" "${OUT}" Franco

  # Act
  run on_terminal_in_steps '3f\033[B\033[B\033[B\n\033[B\033[B\nb' 'is built from' 'q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"Publisher     FRANCO"*"Done. ${OUT} is built from 1 entry."* ]]
}

@test "Enter on Boot picks the boot image and refuses a file that is not there" {
  # Arrange
  head -c 2048 /dev/zero >"${WORK}/boot.bin"
  answers "${WORK}/none.bin" "${WORK}/boot.bin"

  # Act
  run on_terminal '3\033[B\033[B\033[B\033[B\033[B\033[B\n\nq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Boot       ${WORK}/boot.bin"* ]]
  [[ "${shown}" == *"There is no file at ${WORK}/none.bin."* ]]
}

@test "Enter on Emulation steps through none, floppy and hard disk" {
  # Arrange
  local keys='3\033[B\033[B\033[B\033[B\033[B\033[B\033[B\n\n\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"> Emulation  floppy"*"> Emulation  hard-disk"* ]]
  [[ "${final}" == *"> Emulation  none"* ]]
}

@test "Enter on Platform steps through x86, efi, ppc and mac" {
  # Arrange
  local keys='3\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\n\n\n\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"> Platform   efi"*"> Platform   ppc"*"> Platform   mac"* ]]
  [[ "${final}" == *"> Platform   x86"* ]]
}

@test "b builds a bootable image from the Boot field" {
  # Arrange
  head -c 2048 /dev/zero >"${WORK}/boot.bin"
  answers "${SRC}" "${OUT}" "${WORK}/boot.bin"

  # Act
  run on_terminal_in_steps '3f\033[B\n\033[B\033[B\n\033[B\033[B\033[B\033[B\nb' 'is built from' 'q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"Boot          boot.bin, no emulation, x86"*"Done. ${OUT} is built from 1 entry."* ]]
}

@test "Enter on DVD Video turns the VIDEO_TS layout on" {
  # Arrange
  local keys='3\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> DVD Video  [x]"* ]]
}

@test "Enter on Blu-ray turns the BDMV layout on" {
  # Arrange
  local keys='3\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Blu-ray    [x]"* ]]
}

@test "Enter on UDF steps through every revision and back to the default" {
  # Arrange
  local keys='3\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\n\n\n\n\n\n\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown final
  shown="$(screen)"
  final="$(last_frame)"
  [[ "${shown}" == *"> UDF        1.02"*"> UDF        1.50"*"> UDF        2.00"*"> UDF        2.01"*"> UDF        2.50"*"> UDF        2.60"* ]]
  [[ "${final}" == *"> UDF        the tool default"* ]]
}

@test "o saves the layout and its fields as a project" {
  # Arrange
  answers "${SRC}" "${WORK}/trip.enban"

  # Act
  run on_terminal '3foq'

  # Assert
  local shown saved
  shown="$(last_frame)"
  saved="$(<"${WORK}/trip.enban")"
  [[ "${shown}" == *"Saved the project to ${WORK}/trip.enban."* ]]
  [[ "${saved}" == "enban-project=1"$'\n'"fs=iso9660,joliet,udf"$'\n'"label="$'\n'"publisher="$'\n'"date="$'\n'"boot="$'\n'"emulation=none"$'\n'"platform=x86"$'\n'"dvd_video=no"$'\n'"bdmv=no"$'\n'"udf_version="$'\n'"entry=photos"$'\t'"${SRC}" ]]
}

@test "o keeps a project that exists as NAME.bak before it saves" {
  # Arrange
  printf 'older\n' >"${WORK}/trip.enban"
  answers "${SRC}" "${WORK}/trip.enban"

  # Act
  run on_terminal '3foq'

  # Assert
  local shown kept
  shown="$(last_frame)"
  kept="$(<"${WORK}/trip.enban.bak")"
  [[ "${shown}" == *"The earlier ${WORK}/trip.enban is kept as ${WORK}/trip.enban.bak. Saved the project to ${WORK}/trip.enban."* ]]
  [[ "${kept}" == "older" ]]
}

@test "o asks for an entry before it saves" {
  # Arrange
  local keys='3oq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Add a file or folder first: press a or f."* ]]
}

@test "o saves nothing when no file is named" {
  # Arrange
  answers "${SRC}" ""

  # Act
  run on_terminal '3foq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Added photos."* ]]
}

@test "o says when the project cannot be saved" {
  # Arrange
  answers "${SRC}" "${WORK}/missing/trip.enban"

  # Act
  run on_terminal '3foq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Unable to save the project to ${WORK}/missing/trip.enban."* ]]
}

@test "l opens a project into the layout and its fields" {
  # Arrange
  printf '%s\n' enban-project=1 "fs=iso9660,joliet" "label=Kyoto" "entry=notes.txt"$'\t'"${WORK}/notes.txt" >"${WORK}/trip.enban"
  answers "${WORK}/trip.enban"

  # Act
  run on_terminal '3lq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"notes.txt"*"file"* ]]
  [[ "${shown}" == *"Type       ISO9660, Joliet"*"Label      Kyoto"* ]]
  [[ "${shown}" == *"Opened ${WORK}/trip.enban."* ]]
}

@test "l says why a project did not open" {
  # Arrange
  answers "${WORK}/nothing.enban"

  # Act
  run on_terminal '3lq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Not opened: there is no project at ${WORK}/nothing.enban."* ]]
}

@test "l opens nothing when no file is named" {
  # Arrange
  answers ""

  # Act
  run on_terminal '3lq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Type       ISO9660, Joliet, UDF"* ]]
}

@test "a project opened on Build leaves the Settings default alone" {
  # Arrange
  printf '%s\n' enban-project=1 "fs=iso9660" "entry=notes.txt"$'\t'"${WORK}/notes.txt" >"${WORK}/trip.enban"
  answers "${WORK}/trip.enban"

  # Act
  run on_terminal '3l9\033[C\033[Cq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"[Build]"*"> Type       ISO9660, Joliet, UDF"* ]]
}

@test "a build from the Build tab leaves the Settings default alone" {
  # Arrange
  answers "${SRC}" "${OUT}"

  # Act
  run on_terminal_in_steps '3f\033[B\n\033[B\033[B\nb' 'is built from' '9\033[C\033[Cq'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"[Build]"*"> Type       ISO9660, Joliet, UDF"* ]]
}
