#!/bin/sh
set -eu

: "${SCREENS_REPO:?}"
demo=/Users/Shared/demo
rm -rf "${demo}"
mkdir -p "${demo}"
mkdir -p "${demo}/family-2009/kyoto" "${demo}/family-2009/osaka"
head -c 2400000 /dev/urandom >"${demo}/family-2009/kyoto/temple-gate.jpg"
head -c 1800000 /dev/urandom >"${demo}/family-2009/kyoto/garden.jpg"
head -c 2100000 /dev/urandom >"${demo}/family-2009/osaka/castle.jpg"
head -c 4000 /dev/urandom >"${demo}/notes.txt"
head -c 2097152 /dev/urandom >"${demo}/debian-12.iso"
head -c 1048576 /dev/urandom >"${demo}/family-2009.iso"
