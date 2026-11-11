#!/bin/sh
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
image="${ENBAN_TEST_IMAGE:-ubuntu:26.04}"

docker run --rm --privileged \
  -v "${repo}:/repo" \
  -w /repo \
  -e ENBAN_TEST_SHELLS="${ENBAN_TEST_SHELLS:-}" \
  -e ENBAN_TEST_RECORD="${ENBAN_TEST_RECORD:-}" \
  "${image}" \
  sh -c '
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq --no-install-recommends \
      bats zsh dash util-linux sudo ca-certificates git curl python3 procps \
      xorriso cdrskin cdrdao genisoimage sg3-utils dvd+rw-tools bchunk iat udftools mandoc openssl >/dev/null
    i=0
    while [ "$i" -lt 64 ]; do
      [ -e "/dev/loop$i" ] || mknod -m 660 "/dev/loop$i" b 7 "$i"
      i=$((i + 1))
    done
    exec "$@"
  ' sh "$@"
