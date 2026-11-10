#!/bin/sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
SCREENS_REPO=$(cd "${here}/.." && pwd)
export SCREENS_REPO

system=$(uname -s)
if [ "${system}" != Darwin ]; then
  printf 'screens: the screens are recorded on macOS, with VHS and the system terminal tools.\n' >&2
  exit 1
fi
for tool in vhs magick; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    printf 'screens: %s is not installed. install it with: brew install vhs imagemagick\n' "${tool}" >&2
    exit 1
  fi
done

cd "${here}"
status=0
for source in *.tape; do
  [ "${source}" != common.tape ] || continue
  sh ./prepare.sh
  if ! vhs "${source}" >/dev/null 2>&1; then
    printf 'screens: %s did not record.\n' "${source}" >&2
    status=1
  fi
  rm -f scratch.gif
  sh ./cleanup.sh
done
sh ./finish.sh ./*.png
exit "${status}"
