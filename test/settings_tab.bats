#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/pty.bash
source "${BATS_TEST_DIRNAME:-.}/pty.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-stab.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR ENBAN_TEST_GUM APP_PATH ENBAN_QUEUE_WAIT
  export ENBAN_CONFIG="${WORK}/config"
  export ENBAN_TEST_GUM_ANSWERS="${WORK}/answers"
  disk_test_shim stty "case \"\$1\" in size) printf '50 200\\n' ;; *) exec \"\${REAL}\" \"\$@\" ;; esac"
}

teardown() {
  rm -rf "${WORK}"
}

answers() {
  printf '%s\n' "$@" >"${ENBAN_TEST_GUM_ANSWERS}"
}

saved() {
  grep -x "$1" "${ENBAN_CONFIG}/settings"
}

down() {
  local count=0
  while [[ "${count}" -lt "$1" ]]; do
    printf '\\033[B'
    count=$((count + 1))
  done
}

page() {
  local count=0
  while [[ "${count}" -lt "$1" ]]; do
    printf '\\033[C'
    count=$((count + 1))
  done
}

@test "the Settings tab opens on the Write page with its defaults" {
  # Arrange
  local keys='9q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"[Write]  Read   Build   Queue   Events   Look"* ]]
  [[ "${shown}" == *"> Verify     [x] on"*"Eject      [x] on"*"Speed      chosen by the drive"*"Mode       disc at once"*"Finalize   [x] on"*"OPC        [ ] off"* ]]
  [[ "${shown}" == *"Compare the disc with the image after each write."* ]]
  [[ "${shown}" == *"Saved to"*"${ENBAN_CONFIG}/settings"* ]]
}

@test "right opens the Read page with its defaults" {
  # Arrange
  local keys
  keys="9$(page 1)q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *" Write  [Read]"*"> Verify     [x] on"*"Retries    0"*"Skip bad   [ ] off"*"CUE sheet  [ ] off"* ]]
}

@test "the Events page lists the bell, the cancel question and the clean-up" {
  # Arrange
  local keys
  keys="9$(page 4)q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"[Events]"*"> Bell       [x] on"*"Ask first  [x] on"*"Clean up   [x] on"* ]]
  [[ "${shown}" == *"Ring the terminal bell when a job ends."* ]]
}

@test "right stops at the last page" {
  # Arrange
  local keys
  keys="9$(page 9)q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"[Look]"*"> Theme      kodougu"*"The colours of the app."* ]]
}

@test "left steps back a page and stops at the first" {
  # Arrange
  local keys
  keys="9$(page 1)\\033[D\\033[Dq"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"[Write]"*"> Verify"* ]]
}

@test "space turns a switch off, saves it and changes the Write tab's default" {
  # Arrange
  local keys='9 1q'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  saved "write_verify=no"
  [[ "${shown}" == *"Verify     [ ] off"* ]]
}

@test "Enter turns the eject, finalize, OPC and the read verify around" {
  # Arrange
  local keys
  local eject finalize opc read_page
  eject="$(down 1)"
  finalize="$(down 3)"
  opc="$(down 1)"
  read_page="$(page 1)"
  keys="9${eject}\\n${finalize}\\n${opc}\\n${read_page}\\nq"

  # Act
  run on_terminal "${keys}"

  # Assert
  saved "write_eject=no"
  saved "write_finalize=no"
  saved "write_opc=yes"
  saved "read_verify=no"
}

@test "Enter on Mode switches between disc at once and track at once" {
  # Arrange
  local keys
  keys="9$(down 3)\\nq"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  saved "write_mode=tao"
  [[ "${shown}" == *"Mode       track at once"* ]]
}

@test "Enter on Speed sets the default write speed and refuses words" {
  # Arrange
  local keys
  keys="9$(down 2)\\n\\nq"
  answers 8 fast

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  saved "write_speed=8"
  [[ "${shown}" == *"The speed must be a whole number, such as 8."* ]]
}

@test "an empty speed goes back to the drive's choice" {
  # Arrange
  local keys
  keys="9$(down 2)\\n\\nq"
  answers 8 ""

  # Act
  run on_terminal "${keys}"

  # Assert
  saved "write_speed=auto"
}

@test "Enter on Retries sets the read retries and refuses more than 99" {
  # Arrange
  local keys
  local read_page retries
  read_page="$(page 1)"
  retries="$(down 1)"
  keys="9${read_page}${retries}\\n\\nq"
  answers 5 100

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  saved "read_retries=5"
  [[ "${shown}" == *"The retries must be a whole number from 0 to 99."* ]]
}

@test "space turns on skipping bad sectors and the CUE sheet of read" {
  # Arrange
  local keys
  local read_page skip cue
  read_page="$(page 1)"
  skip="$(down 2)"
  cue="$(down 1)"
  keys="9${read_page}${skip} ${cue} q"

  # Act
  run on_terminal "${keys}"

  # Assert
  saved "read_ignore=yes"
  saved "read_cue=yes"
}

@test "Enter on Type steps through the file systems build writes" {
  # Arrange
  local keys
  keys="9$(page 2)\\nq"

  # Act
  run on_terminal "${keys}"

  # Assert
  saved "build_fs=iso9660,joliet"
}

@test "Enter on Wait sets the queue wait and refuses words" {
  # Arrange
  local keys
  keys="9$(page 3)\\n\\nq"
  answers 30 soon

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  saved "queue_wait=30"
  [[ "${shown}" == *"The wait must be a whole number of seconds."* ]]
}

@test "space turns the bell, the cancel question and the clean-up off" {
  # Arrange
  local keys
  local events_page next
  events_page="$(page 4)"
  next="$(down 1)"
  keys="9${events_page} ${next} ${next} q"

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  saved "event_bell=no"
  saved "event_confirm=no"
  saved "event_clean=no"
  [[ "${shown}" == *"Delete what a cancelled or failed job left half written."* ]]
}

@test "Enter on Theme picks a theme and refuses one that does not exist" {
  # Arrange
  local keys
  keys="9$(page 5)\\n\\nq"
  answers nord sepia

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  saved "theme=nord"
  [[ "${shown}" == *"There is no theme named sepia."* ]]
}

@test "a theme from the environment is shown and kept out of the file" {
  # Arrange
  local keys
  keys="9 $(page 5)\\nq"

  # Act
  ENBAN_THEME=dracula run on_terminal "${keys}"

  # Assert
  local shown themes
  shown="$(last_frame)"
  themes="$(grep -c '^theme=' "${ENBAN_CONFIG}/settings" || true)"
  [[ "${shown}" == *"Theme      dracula, from ENBAN_THEME"* ]]
  [[ "${shown}" == *"ENBAN_THEME sets the theme. Unset it to choose one here."* ]]
  [[ "${themes}" == "0" ]]
}

@test "the Settings tab starts from the settings file" {
  # Arrange
  mkdir -p "${ENBAN_CONFIG}"
  printf '%s\n' write_verify=no write_speed=4 write_mode=tao >"${ENBAN_CONFIG}/settings"

  # Act
  run on_terminal '9q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"> Verify     [ ] off"*"Speed      4x"*"Mode       track at once"* ]]
}

@test "the Settings tab says when the settings cannot be saved" {
  # Arrange
  printf 'not a folder\n' >"${WORK}/blocked"
  export ENBAN_CONFIG="${WORK}/blocked/enban"

  # Act
  run on_terminal '9 q'

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Unable to save the settings to ${ENBAN_CONFIG}/settings."* ]]
}

@test "the Settings tab ignores other keys" {
  # Arrange
  local keys='9zq'

  # Act
  run on_terminal "${keys}"

  # Assert
  local shown
  shown="$(last_frame)"
  [[ "${shown}" == *"Settings"*"> Verify"* ]]
}
