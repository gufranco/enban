#!/bin/sh
set -eu

version=${1:?version required}
root=$(cd "$(dirname "$0")/../.." && pwd)
core="${root}/lib/core.sh"

if ! grep -q '^ENBAN_VERSION=' "${core}"; then
  printf 'no ENBAN_VERSION assignment found in %s\n' "${core}" >&2
  exit 1
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/enban-version-XXXXXX")
sed "s/^ENBAN_VERSION=\".*\"$/ENBAN_VERSION=\"${version}\"/" "${core}" >"${tmp}"
cat "${tmp}" >"${core}"
rm -f "${tmp}"

reported=$("${root}/bin/enban" --version)
printf 'version set to %s\n' "${reported}"
