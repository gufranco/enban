#!/usr/bin/env bats
# shellcheck disable=SC2016

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-app.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
}

teardown() {
  rm -rf "${WORK}"
}

@test "enban opens in the alternate screen and gives it back on q" {
  # Arrange
  local keys="q"

  # Act
  run on_terminal "${keys}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *$'\033[?1049h'* ]]
  [[ "${output}" == *$'\033[?1049l'* ]]
  [[ "${output}" == *$'\033[?25h'* ]]
}

@test "enban draws the home tab with its jobs" {
  # Arrange
  local keys="q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(screen)"
  [[ "${shown}" == *"What would you like to do?"* ]]
  [[ "${shown}" == *"Write image to disc"* ]]
}

@test "a digit switches to that tab" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '50 80\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  local keys="3q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"Build image from files"*"Disc layout"* ]]
}

@test "Tab moves to the next tab" {
  # Arrange
  local keys='\tq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"Write image to disc"*"> Image      none chosen, press Enter"* ]]
}

@test "Tab past the last tab comes back to Home" {
  # Arrange
  local keys='9\tq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"What would you like to do?"* ]]
}

@test "the arrows move the focus down the list of jobs" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '24 60\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  local keys='\033[B\033[Bq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"> Read disc to image"* ]]
}

@test "the focus stops at the ends of the list and ignores left and right" {
  # Arrange
  local keys='\033[A\033[D\033[C\033[B\033[B\033[B\033[B\033[B\033[Bq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"> Discovery test"* ]]
}

@test "enter opens the tab of the focused job" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '24 60\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  local keys='\033[B\033[B\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"Read disc to image"*"> Image      none chosen, press Enter"* ]]
}

@test "the arrows and enter do nothing on a tab still to come" {
  # Arrange
  local keys='5\033[B\nq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"Discovery test arrives in a coming release."* ]]
}

@test "? shows the keys and the next key closes them" {
  # Arrange
  local keys='?xq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(screen)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"tab         next tab"* ]]
  local final
  final="$(last_frame)"
  [[ "${final}" == *"What would you like to do?"* ]]
}

@test "escape and other keys change nothing" {
  # Arrange
  local keys='\033[Zxq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"> Write image to disc"* ]]
}

@test "the disc pane says when no drive is chosen" {
  # Arrange
  local keys="q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"No drive chosen."*"Start enban with --drive DRIVE,"*"or set ENBAN_DRIVE."* ]]
}

@test "the disc pane describes the disc in the drive" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
  : >"${WORK}/disc.iso"
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  local keys="q"

  # Act
  run on_terminal "${keys}" --drive "stdio:${WORK}/disc.iso"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"Profile      DVD-R sequential recording"* ]]
  [[ "${shown}" == *"Free         2298496 sectors, 4.7 GB"* ]]
  [[ "${shown}" == *"DVD-R loaded, 4.7 GB free."* ]]
}

@test "the disc pane says when the drive cannot be read" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
  local keys="q"

  # Act
  run on_terminal "${keys}" --drive="stdio:${WORK}/missing/disc.iso"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Unable to read the drive."* ]]
}

@test "the disc pane names the macOS gap" {
  # Arrange
  local keys="q"

  # Act
  ENBAN_OS=Darwin run on_terminal "${keys}" --drive /dev/disk4

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Reading a drive is not supported on macOS yet."* ]]
}

@test "a wide terminal draws the two panes side by side" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '40 140\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  local keys="q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown rows
  shown="$(last_frame)"
  rows="$(grep -c 'What would you like to do?.*Disc' <<<"${shown}")"
  [[ "${rows}" -eq 1 ]]
}

@test "the app rejects --json, which only info takes" {
  # Arrange
  local option=--json

  # Act
  run disk_test_run enban --drive /dev/sr0 "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--json' works only with info. run 'enban help' for usage." ]]
}

@test "the app rejects a stray argument after its options" {
  # Arrange
  local extra=burn

  # Act
  run disk_test_run enban --drive /dev/sr0 "${extra}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unexpected argument 'burn'. run 'enban help' for usage." ]]
}

@test "enter changes nothing and Ctrl+D closes the app" {
  # Arrange
  local keys='\n\004'

  # Act
  run on_terminal "${keys}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *$'\033[?1049l'* ]]
}

@test "the end of input reads as the end of the session" {
  # Arrange
  local call='disk_app_key; printf "%s\n" "${DISK_APP_KEY}"'

  # Act
  run disk_test_call eval "${call}" </dev/null

  # Assert
  [[ "${output}" == "eof" ]]
}

@test "the mono theme draws the current tab in brackets" {
  # Arrange
  local keys="q"

  # Act
  run on_terminal "${keys}" --theme mono

  # Assert
  local shown
  shown="$(screen)"
  [[ "${shown}" == *"[0 Home]"* ]]
}

@test "enban never opens the app without a terminal" {
  # Arrange
  local input=/dev/null

  # Act
  run disk_test_run enban <"${input}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the app needs a terminal. run 'enban help' for usage." ]]
}

@test "a terminal that reports no size gets 80 columns" {
  # Arrange
  local call='disk_app_size; printf "%s %s\n" "${DISK_APP_ROWS}" "${DISK_APP_COLS}"'

  # Act
  run disk_test_call eval "${call}" </dev/null

  # Assert
  [[ "${output}" == "24 80" ]]
}

@test "a terminal that reports a size of zero gets 80 columns" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '0 0\\n' ;; esac"
  local call='disk_app_size; printf "%s %s\n" "${DISK_APP_ROWS}" "${DISK_APP_COLS}"'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "24 80" ]]
}

@test "a narrow terminal is drawn at 60 columns" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '10 40\\n' ;; esac"
  local call='disk_app_size; printf "%s\n" "${DISK_APP_COLS}"'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "60" ]]
}

@test "leaving warns when the terminal still hides typing" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in -a) printf 'speed 9600 baud; -echo icanon\\n' ;; esac"
  local call='DISK_APP_STTY=changed disk_app_leave'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: warning: the terminal still hides what you type. run stty sane to restore it."* ]]
}

@test "leaving draws the hidden-typing warning with gum" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in -a) printf 'speed 9600 baud; -echo icanon\\n' ;; esac"
  local call='disk_ui_setup && DISK_APP_STTY=changed disk_app_leave'

  # Act
  ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log" run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"WARN enban: the terminal still hides what you type. run stty sane to restore it."* ]]
}

@test "leaving twice restores the terminal only once" {
  # Arrange
  disk_test_shim stty "printf 'called %s\\n' \"\$*\" >>'${WORK}/stty.log'"
  local call='disk_app_leave'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ ! -e "${WORK}/stty.log" ]]
}

@test "a colour turns into its red, green and blue parts" {
  # Arrange
  local colour="#F25D94"

  # Act
  run disk_test_call disk_app_rgb "${colour}"

  # Assert
  [[ "${output}" == "242;93;148" ]]
}

@test "a wide terminal moves the focus across the grid of jobs" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '40 140\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  local keys='\033[B\033[C\033[A\033[D\033[B\033[B\033[Cq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"> Discovery test"* ]]
}

@test "the Discovery tab names the job that arrives there" {
  # Arrange
  local keys="5q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local final
  final="$(last_frame)"
  [[ "${final}" == *"Discovery test arrives in a coming release."* ]]
}

@test "a wide terminal shows the drive and its disc in the header" {
  # Arrange
  [[ "${ENBAN_TEST_OS}" == "Linux" ]] || skip "macOS reads the drive through drutil"
  : >"${WORK}/disc.iso"
  disk_test_drive 0011 "DVD-R sequential recording" 2298496 22160 11080
  disk_test_shim stty "case \"\$1\" in size) printf '40 140\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  local keys="q"

  # Act
  run on_terminal "${keys}" --drive "stdio:${WORK}/disc.iso"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${status}" -eq 0 ]]
  [[ "${shown}" == *"drive stdio:${WORK}/disc.iso  DVD-R"* ]]
}

@test "q quits even while the keys are shown" {
  # Arrange
  local keys='?q'

  # Act
  run on_terminal "${keys}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *$'\033[?1049l'* ]]
}

@test "two panes keep their bottoms level when a long line wraps" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '40 100\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  local keys="3q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown bottoms
  shown="$(last_frame)"
  bottoms="$(grep -c "$(printf '\342\225\260').*$(printf '\342\225\260')" <<<"${shown}" || true)"
  [[ "${bottoms}" -eq 1 ]]
}

@test "a frame never grows past the terminal and keeps the focus in view" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '20 140\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  local keys
  keys="7$(printf '\\033[B%.0s' {1..14})q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown rows
  shown="$(last_frame)"
  rows="$(awk '/q quit/ { print NR; exit }' <<<"${shown}")"
  [[ "${rows}" -le 20 ]]
  [[ "${shown}" == *"enban"*"> Mount"* ]]
}

@test "a clipped pane keeps its title above the focus" {
  # Arrange
  disk_test_shim stty "case \"\$1\" in size) printf '14 140\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
  local keys
  keys="7$(printf '\\033[B%.0s' {1..14})q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Tools"*"> Mount"* ]]
  [[ "${shown}" != *"Erase disc"* ]]
}
