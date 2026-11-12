#!/bin/sh
{ set +x; } 2>/dev/null

work="$1"
action="$2"
shift 2
system=/usr/sbin:/usr/bin:/sbin:/bin

block() {
  while [ "$#" -gt 0 ]; do
    [ "$1" != -b ] || {
      printf '%s\n' "$2"
      return 0
    }
    shift
  done
}

case "${action}" in
loop-setup)
  image=""
  while [ "$#" -gt 0 ]; do
    [ "$1" != -f ] || image="$2"
    shift
  done
  device="$(sudo env PATH="${system}" losetup -f --show -r "${image}")" || exit 1
  printf 'Mapped file %s as %s.\n' "${image}" "${device}"
  ;;
mount)
  device="$(block "$@")"
  point="${work}/media/$(basename "${device}")"
  mkdir -p "${point}"
  if ! sudo env PATH="${system}" mount -o ro "${device}" "${point}" 2>/dev/null; then
    printf 'Error mounting %s: wrong fs type\n' "${device}" >&2
    exit 1
  fi
  printf 'Mounted %s at %s\n' "${device}" "${point}"
  ;;
unmount)
  device="$(block "$@")"
  sudo env PATH="${system}" umount "${device}" || exit 1
  printf 'Unmounted %s.\n' "${device}"
  ;;
loop-delete)
  device="$(block "$@")"
  sudo env PATH="${system}" losetup -d "${device}"
  ;;
*) exit 2 ;;
esac
