#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-cli.XXXXXX")"
}

teardown() {
  rm -rf "${WORK}"
}

minimal_path() {
  local bin="${WORK}/bin"
  local tool found
  mkdir -p "${bin}"
  for tool in sh uname awk sed tr wc cat dirname env; do
    found="$(command -v "${tool}")"
    ln -s "${found}" "${bin}/${tool}"
  done
  printf '%s' "${bin}"
}

@test "enban help prints the usage page on stdout" {
  # Arrange
  local program=enban

  # Act
  run disk_test_run "${program}" help

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "enban - write, read, build and verify CD, DVD and Blu-ray discs" ]]
}

@test "enban version names the program and its version" {
  # Arrange
  local version
  version="$(sed -n 's/^ENBAN_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

  # Act
  run disk_test_run enban --version

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "enban ${version}" ]]
}

@test "enban rejects an unknown command with a usage hint" {
  # Arrange
  local command=burn

  # Act
  run disk_test_run enban "${command}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unknown command 'burn'. run 'enban help' for usage." ]]
}

@test "enban rejects an unknown option with a usage hint" {
  # Arrange
  local option=--fast

  # Act
  run disk_test_run enban "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: unknown option '--fast'. run 'enban help' for usage." ]]
}

@test "enban doctor lists the drive tools of this system" {
  # Arrange
  local expected
  case "${ENBAN_TEST_OS}" in
  Darwin) expected="drutil" ;;
  *) expected="xorriso" ;;
  esac

  # Act
  run disk_test_run enban doctor

  # Assert
  [[ "${output}" =~ (^|$'\n')${expected}\  ]]
  [[ "${output}" =~ (^|$'\n')dd\ +ok\  ]]
}

@test "enban doctor fails and names a missing core tool" {
  # Arrange
  local bin
  bin="$(minimal_path)"

  # Act
  run env PATH="${bin}" "${bin}/sh" "${REPO_DIR}/bin/enban" doctor

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" =~ (^|$'\n')dd\ +missing\ +required ]]
}

@test "enban doctor warns about cdrdao on Linux without failing on it" {
  # Arrange
  local farm
  farm="$(disk_test_farm cdrdao)"

  # Act
  run disk_test_run_path "${farm}" enban doctor

  # Assert
  [[ "${output}" =~ (^|$'\n')cdrdao\ +warn\ +cdrdao\ package ]]
}

@test "enban --theme without a value stops with the usage hint" {
  # Arrange
  local option=--theme

  # Act
  run disk_test_run enban version "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--theme' needs a value. run 'enban help' for usage." ]]
}

@test "enban stops on an unknown theme" {
  # Arrange
  local option=--theme=solarized

  # Act
  run disk_test_run enban "${option}" version

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"got: solarized"* ]]
}

@test "enban runs when called by name from PATH" {
  # Arrange
  local -a shell_words
  read -r -a shell_words <<<"${ENBAN_TEST_SHELL:-sh}"

  # Act
  run bash -c 'cd "$1" && shift && PATH="$PWD:$PATH" "$@" enban version' _ "${REPO_DIR}/bin" "${shell_words[@]}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "enban "* ]]
}

@test "enban man page passes mandoc lint" {
  # Arrange
  local page="${REPO_DIR}/man/enban.1"

  # Act
  run mandoc -T lint "${page}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

theme_everywhere() {
  local page
  page="$(disk_test_run enban help)" || return 1
  grep -q -- '^  --theme ' <<<"${page}" || return 1
  grep -qF -- '\-\-theme' "${REPO_DIR}/man/enban.1" || return 2
  grep -q -- '"--theme"' "${REPO_DIR}/completions/enban.bash" || return 3
  grep -q -- "'--theme\[" "${REPO_DIR}/completions/_enban" || return 4
  grep -q -- '-l theme ' "${REPO_DIR}/completions/enban.fish" || return 5
}

@test "enban help, man page and completions list the same options" {
  # Arrange
  local option=--theme

  # Act
  run theme_everywhere "${option}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

info_everywhere() {
  local page option
  page="$(disk_test_run enban help)" || return 1
  grep -q -- '^  enban info ' <<<"${page}" || return 1
  grep -q -- '^\.B enban info$' "${REPO_DIR}/man/enban.1" || return 2
  grep -q -- '-W "info ' "${REPO_DIR}/completions/enban.bash" || return 3
  grep -q -- "'info:" "${REPO_DIR}/completions/_enban" || return 4
  grep -q -- '-a info ' "${REPO_DIR}/completions/enban.fish" || return 5
  for option in drive json; do
    grep -q -- "^  --${option} " <<<"${page}" || return 6
    grep -qF -- "\\-\\-${option}" "${REPO_DIR}/man/enban.1" || return 7
    grep -q -- "--${option}" "${REPO_DIR}/completions/enban.bash" || return 8
    grep -q -- "'--${option}\[" "${REPO_DIR}/completions/_enban" || return 9
    grep -q -- "-l ${option} " "${REPO_DIR}/completions/enban.fish" || return 10
  done
}

@test "enban help, man page and completions list info with --drive and --json" {
  # Arrange
  local command=info

  # Act
  run info_everywhere "${command}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

write_everywhere() {
  local page option
  page="$(disk_test_run enban help)" || return 1
  grep -q -- '^  enban write ' <<<"${page}" || return 1
  grep -q -- '^\.B enban write$' "${REPO_DIR}/man/enban.1" || return 2
  grep -q -- ' write ' "${REPO_DIR}/completions/enban.bash" || return 3
  grep -q -- "'write:" "${REPO_DIR}/completions/_enban" || return 4
  grep -q -- '-a write ' "${REPO_DIR}/completions/enban.fish" || return 5
  for option in speed no-verify no-eject; do
    grep -q -- "^  --${option} " <<<"${page}" || return 6
    grep -qF -- "\\-\\-${option//-/\\-}" "${REPO_DIR}/man/enban.1" || return 7
    grep -q -- "--${option}" "${REPO_DIR}/completions/enban.bash" || return 8
    grep -q -- "'--${option}\[" "${REPO_DIR}/completions/_enban" || return 9
    grep -q -- "-l ${option} " "${REPO_DIR}/completions/enban.fish" || return 10
  done
}

@test "enban help, man page and completions list write and its options" {
  # Arrange
  local command=write

  # Act
  run write_everywhere "${command}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

command_everywhere() {
  local page
  page="$(disk_test_run enban help)" || return 1
  grep -q -- "^  enban $1 " <<<"${page}" || return 1
  grep -q -- "^\\.B enban $1\$" "${REPO_DIR}/man/enban.1" || return 2
  grep -q -- " $1 " "${REPO_DIR}/completions/enban.bash" || return 3
  grep -q -- "'$1:" "${REPO_DIR}/completions/_enban" || return 4
  grep -q -- "-a $1 " "${REPO_DIR}/completions/enban.fish" || return 5
}

@test "enban help, man page and completions list read" {
  # Arrange
  local command=read

  # Act
  run command_everywhere "${command}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "enban help, man page and completions list verify" {
  # Arrange
  local command=verify

  # Act
  run command_everywhere "${command}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "enban help, man page and completions list build" {
  # Arrange
  local command=build

  # Act
  run command_everywhere "${command}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

options_everywhere() {
  local page option
  page="$(disk_test_run enban help)" || return 1
  for option in "$@"; do
    grep -q -- "^  --${option} " <<<"${page}" || return 2
    grep -qF -- "\\-\\-${option//-/\\-}" "${REPO_DIR}/man/enban.1" || return 3
    grep -q -- "--${option}" "${REPO_DIR}/completions/enban.bash" || return 4
    grep -q -- "'--${option}\[" "${REPO_DIR}/completions/_enban" || return 5
    grep -q -- "-l ${option} " "${REPO_DIR}/completions/enban.fish" || return 6
  done
}

@test "enban help, man page and completions list --fs and --label" {
  # Arrange
  local first=fs

  # Act
  run options_everywhere "${first}" label

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "enban help, man page and completions list the build identifiers" {
  # Arrange
  local first=publisher

  # Act
  run options_everywhere "${first}" preparer application system-id volume-set date iso-level boot emulation platform load-sectors boot-info-table dvd-video bdmv udf-version

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "enban help, man page and completions list erase and --full" {
  # Arrange
  local command=erase

  # Act
  run command_everywhere "${command}"

  # Assert
  local options_status
  options_status=0
  options_everywhere full || options_status=$?
  [[ "${status}" -eq 0 ]]
  [[ "${options_status}" -eq 0 ]]
}

@test "enban help, man page and completions list checksum" {
  # Arrange
  local command=checksum

  # Act
  run command_everywhere "${command}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "enban help, man page and completions list queue" {
  # Arrange
  local command=queue

  # Act
  run command_everywhere "${command}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "enban help, man page and completions list discovery, --sectors and --csv" {
  # Arrange
  local command=discovery

  # Act
  run command_everywhere "${command}"

  # Assert
  local options_status
  options_status=0
  options_everywhere sectors csv || options_status=$?
  [[ "${status}" -eq 0 ]]
  [[ "${options_status}" -eq 0 ]]
}

@test "enban help, man page and completions list --verify and --eject" {
  # Arrange
  local first=verify

  # Act
  run options_everywhere "${first}" eject

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "enban help, man page and completions list sector and --lba" {
  # Arrange
  local command=sector

  # Act
  run command_everywhere "${command}"

  # Assert
  local options_status
  options_status=0
  options_everywhere lba || options_status=$?
  [[ "${status}" -eq 0 ]]
  [[ "${options_status}" -eq 0 ]]
}

@test "enban help, man page and completions list cue and its options" {
  # Arrange
  local command=cue

  # Act
  run command_everywhere "${command}"

  # Assert
  local options_status
  options_status=0
  options_everywhere title performer pregap || options_status=$?
  [[ "${status}" -eq 0 ]]
  [[ "${options_status}" -eq 0 ]]
}

@test "enban help, man page and completions list the drive tools and convert" {
  # Arrange
  local first=close

  # Act
  run command_everywhere "${first}"

  # Assert
  local each status_all=0
  for each in speed region booktype convert; do
    command_everywhere "${each}" || status_all=1
  done
  options_everywhere raw finalize set || status_all=1
  [[ "${status}" -eq 0 ]]
  [[ "${status_all}" -eq 0 ]]
}

@test "enban help, man page and completions list the image tools and speeds" {
  # Arrange
  local first=label

  # Act
  run command_everywhere "${first}"

  # Assert
  local each status_all=0
  for each in layerbreak mount unmount speeds; do
    command_everywhere "${each}" || status_all=1
  done
  [[ "${status}" -eq 0 ]]
  [[ "${status_all}" -eq 0 ]]
}
