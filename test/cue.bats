#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/enban-cue.XXXXXX")"
  unset KODOUGU_THEME KODOUGU_ACCENT ENBAN_THEME ENBAN_DRIVE NO_COLOR
  CUE="${WORK}/album.cue"
}

teardown() {
  rm -rf "${WORK}"
}

le32() {
  printf '\\%03o\\%03o\\%03o\\%03o' $(($1 & 255)) $((($1 >> 8) & 255)) $((($1 >> 16) & 255)) $((($1 >> 24) & 255))
}

le16() {
  printf '\\%03o\\%03o' $(($1 & 255)) $((($1 >> 8) & 255))
}

wav() {
  local file="$1" rate="$2" bits="$3" channels="$4" seconds="$5"
  local block=$((channels * bits / 8))
  local bytes=$((rate * block * seconds))
  local riff fmt_size format chans hz per_second align depth data
  riff="$(le32 $((36 + bytes)))"
  fmt_size="$(le32 16)"
  format="$(le16 1)"
  chans="$(le16 "${channels}")"
  hz="$(le32 "${rate}")"
  per_second="$(le32 $((rate * block)))"
  align="$(le16 "${block}")"
  depth="$(le16 "${bits}")"
  data="$(le32 "${bytes}")"
  printf '%b' "RIFF${riff}WAVEfmt ${fmt_size}${format}${chans}${hz}${per_second}${align}${depth}data${data}" >"${file}"
  head -c "${bytes}" /dev/zero >>"${file}"
}

tone() {
  ffmpeg -nostdin -v error -f lavfi -i "sine=frequency=440:duration=$2" -ar 22050 -ac 1 "$1" 2>/dev/null
}

wav_shape() {
  local header
  header="$(od -An -tu1 -j 22 -N 14 "$1")"
  awk '{ printf "%d %d %d", $3 + $4 * 256 + $5 * 65536 + $6 * 16777216, $13 + $14 * 256, $1 + $2 * 256 }' <<<"${header}"
}

@test "enban cue decodes FLAC and MP3 tracks into CD audio beside the sheet" {
  # Arrange
  tone "${WORK}/Opening.flac" 2
  tone "${WORK}/Closing.mp3" 1
  wav "${WORK}/Middle.wav" 44100 16 2 1

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/Opening.flac" "${WORK}/Middle.wav" "${WORK}/Closing.mp3" </dev/null

  # Assert
  local sheet first last
  sheet="$(<"${CUE}")"
  first="$(wav_shape "${WORK}/album tracks/01 Opening.wav")"
  last="$(wav_shape "${WORK}/album tracks/03 Closing.wav")"
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "Decoding the compressed tracks into ${WORK}/album tracks with ffmpeg." ]]
  [[ "${first}" == "44100 16 2" ]]
  [[ "${last}" == "44100 16 2" ]]
  [[ "${sheet}" == *"FILE \"${WORK}/album tracks/01 Opening.wav\" WAVE"*"FILE \"Middle.wav\" WAVE"*"FILE \"${WORK}/album tracks/03 Closing.wav\" WAVE"* ]]
}

@test "enban cue needs ffmpeg for a compressed track" {
  # Arrange
  local farm
  tone "${WORK}/Opening.flac" 1
  farm="$(disk_test_farm ffmpeg)"

  # Act
  run disk_test_run_path "${farm}" enban cue "${CUE}" "${WORK}/Opening.flac" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: cue needs ffmpeg to turn FLAC, MP3, OGG, M4A and the like into CD audio. install it and try again." ]]
  [[ ! -e "${WORK}/album tracks" ]]
}

@test "enban cue never decodes into a folder that already exists" {
  # Arrange
  tone "${WORK}/Opening.flac" 1
  mkdir "${WORK}/album tracks"

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/Opening.flac" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${WORK}/album tracks already exists." ]]
}

@test "enban cue removes what it decoded when a track will not decode" {
  # Arrange
  tone "${WORK}/Opening.flac" 1
  printf 'not audio' >"${WORK}/Broken.mp3"

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/Opening.flac" "${WORK}/Broken.mp3" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"enban: ffmpeg could not decode ${WORK}/Broken.mp3." ]]
  [[ ! -e "${WORK}/album tracks" ]]
  [[ ! -e "${CUE}" ]]
}

@test "enban cue writes a CUE sheet with a track for each WAV file" {
  # Arrange
  wav "${WORK}/01 Opening.wav" 44100 16 2 3
  wav "${WORK}/02 Closing.wav" 44100 16 2 2

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/01 Opening.wav" "${WORK}/02 Closing.wav" --title "Trip 2024" --performer "Family" </dev/null

  # Assert
  local sheet wanted
  sheet="$(cat "${CUE}")"
  wanted="$(printf '%s\n' 'TITLE "Trip 2024"' 'PERFORMER "Family"' 'FILE "01 Opening.wav" WAVE' '  TRACK 01 AUDIO' '    TITLE "01 Opening"' '    INDEX 01 00:00:00' 'FILE "02 Closing.wav" WAVE' '  TRACK 02 AUDIO' '    TITLE "02 Closing"' '    PREGAP 00:02:00' '    INDEX 01 00:00:00')"
  [[ "${status}" -eq 0 ]]
  [[ "${sheet}" == "${wanted}" ]]
  [[ "${lines[0]}" == "Tracks       2" ]]
  [[ "${lines[1]}" == "Length       00:07" ]]
  [[ "${lines[2]}" == "Done. ${CUE} lists 2 tracks." ]]
}

@test "enban cue leaves out the gap with --pregap 0 and names a file outside its folder in full" {
  # Arrange
  mkdir -p "${WORK}/songs"
  wav "${WORK}/songs/a.wav" 44100 16 2 1
  wav "${WORK}/songs/b.wav" 44100 16 2 1

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/songs/a.wav" "${WORK}/songs/b.wav" --pregap 0 </dev/null

  # Assert
  local sheet
  sheet="$(cat "${CUE}")"
  [[ "${status}" -eq 0 ]]
  [[ "${sheet}" == "FILE \"${WORK}/songs/a.wav\" WAVE"* ]]
  [[ "${sheet}" != *"PREGAP"* ]]
  [[ "${sheet}" != *"PERFORMER"* ]]
  [[ "${lines[1]}" == "Length       00:02" ]]
}

@test "enban cue refuses audio that is not CD audio" {
  # Arrange
  wav "${WORK}/hi.wav" 48000 24 2 1

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/hi.wav" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${WORK}/hi.wav is 48000 Hz, 24-bit, 2 channels; an audio CD needs 44100 Hz, 16-bit, 2 channels." ]]
  [[ ! -e "${CUE}" ]]
}

@test "enban cue refuses a file that is not WAV" {
  # Arrange
  printf 'not a wave' >"${WORK}/song.txt"

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/song.txt" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${WORK}/song.txt is not a WAV file." ]]
}

@test "enban cue refuses a WAV file with no audio data" {
  # Arrange
  printf 'RIFF\004\000\000\000WAVE' >"${WORK}/empty.wav"

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/empty.wav" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: ${WORK}/empty.wav is not a WAV file." ]]
}

@test "enban cue refuses tracks longer than a CD holds" {
  # Arrange
  wav "${WORK}/long.wav" 44100 16 2 1
  printf '\000\000\000\100' | dd of="${WORK}/long.wav" bs=1 seek=40 conv=notrunc 2>/dev/null

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/long.wav" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: the tracks run 101:26, longer than the 80:00 a CD-R holds." ]]
}

@test "enban cue says when a track is missing" {
  # Arrange
  local track="${WORK}/gone.wav"

  # Act
  run disk_test_run enban cue "${CUE}" "${track}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no file at ${track}." ]]
}

@test "enban cue never overwrites a file" {
  # Arrange
  wav "${WORK}/a.wav" 44100 16 2 1
  printf 'keep\n' >"${CUE}"

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/a.wav" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: stopped: ${CUE} already exists." ]]
}

@test "enban cue refuses a double quote in a title" {
  # Arrange
  wav "${WORK}/a.wav" 44100 16 2 1

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/a.wav" --title 'The "Best"' </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --title and --performer cannot hold a double quote." ]]
}

@test "enban cue refuses a pregap that is not a number" {
  # Arrange
  wav "${WORK}/a.wav" 44100 16 2 1

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/a.wav" --pregap long </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: --pregap must be a whole number of seconds, got: long" ]]
}

@test "enban cue draws its result with gum" {
  # Arrange
  wav "${WORK}/a.wav" 44100 16 2 1
  export ENBAN_TEST_GUM=1 ENBAN_TEST_GUM_LOG="${WORK}/gum.log"

  # Act
  run disk_test_run enban cue "${CUE}" "${WORK}/a.wav" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  grep -qF -- "Done. ${CUE} lists 1 track." "${WORK}/gum.log"
}

@test "enban cue needs a CUE file and at least one track" {
  # Arrange
  local cue="${CUE}"

  # Act
  run disk_test_run enban cue "${cue}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: cue needs a CUE file to create and at least one WAV track. run 'enban help' for usage." ]]
}

@test "write refuses --title, which only cue takes" {
  # Arrange
  local option=--title

  # Act
  run disk_test_run enban write "${CUE}" --drive /dev/sr0 "${option}" x </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: option '--title' works only with cue. run 'enban help' for usage." ]]
}

@test "enban cue needs the CUE file's folder to exist" {
  # Arrange
  wav "${WORK}/a.wav" 44100 16 2 1

  # Act
  run disk_test_run enban cue "${WORK}/none/album.cue" "${WORK}/a.wav" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "enban: no folder at ${WORK}/none." ]]
}
