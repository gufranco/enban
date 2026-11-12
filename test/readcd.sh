#!/bin/sh
{ set +x; } 2>/dev/null

state="$1"
shift
log="${state%/*}/readcd.log"
printf '%s\n' "$*" >>"${log}"

value() {
  sed -n "s/^$1=//p" "${state}" 2>/dev/null | sed -n '$p'
}

file=""
range=""
noerror=n
clone=n
for arg in "$@"; do
  case "${arg}" in
  f=*) file="${arg#f=}" ;;
  sectors=*) range="${arg#sectors=}" ;;
  -noerror) noerror=y ;;
  -clone)
    clone=y
    noerror=y
    ;;
  *) : ;;
  esac
done
start="${range%-*}"
end="${range#*-}"
backing="$(value backing)"
bad="$(value bad)"
fail_read="$(value fail_read)"
fail_after="$(value fail_after)"
calls="$(wc -l <"${log}")"
[ -z "${fail_after}" ] || [ "${calls}" -le "${fail_after}" ] || fail_read=1
size="$(wc -c <"${backing}")"
held=$((size / 2048))
record=2048
[ "${clone}" = n ] || record=2448
if [ "${fail_read}" = 1 ]; then
  printf 'readcd: Cannot open SCSI driver.\n' >&2
  exit 255
fi
[ "${file}" = - ] || : >"${file}"
[ "${clone}" = n ] || : >"${file}.toc"

emit() {
  if [ "${file}" = - ]; then
    cat
  else
    cat >>"${file}"
  fi
}

subchannel() {
  escapes="$(awk -v lba="$1" '
    function bcd(n) { return int(n / 10) * 16 + n % 10 }
    function msf(n, at) { q[at] = bcd(int(n / 4500)); q[at + 1] = bcd(int(n / 75) % 60); q[at + 2] = bcd(n % 75) }
    BEGIN {
      q[0] = 65; q[1] = 1; q[2] = 1; msf(lba, 3); q[6] = 0; msf(lba + 150, 7); q[10] = 0; q[11] = 0
      for (k = 0; k < 12; k++)
        for (j = 7; j >= 0; j--) printf "\\0%03o", int(q[k] / 2 ^ j) % 2 * 64
    }')"
  printf '%b' "${escapes}"
}

clone_sector() {
  printf '\000\377\377\377\377\377\377\377\377\377\377\000\000\002\000\001'
  dd if="${backing}" bs=2048 skip="$1" count=1 2>/dev/null
  head -c 288 /dev/zero
  subchannel "$1"
}

copy() {
  [ "$2" -gt "$1" ] || return 0
  if [ "${clone}" = n ]; then
    dd if="${backing}" bs=2048 skip="$1" count=$(($2 - $1)) 2>/dev/null | emit
    return 0
  fi
  at="$1"
  while [ "${at}" -lt "$2" ]; do
    clone_sector "${at}" | emit
    at=$((at + 1))
  done
}

finish() {
  printf 'Time total: 0.250sec\n' >&2
  printf 'Read %d.00 kB at 1024.0 kB/sec.\n' $((($1 - start) * 2)) >&2
}

unreadable() {
  [ "$1" -ge "${held}" ] || [ "$1" -eq "${bad}" ]
}

printf 'end:  %8d\n' "${end}" >&2
[ -n "${bad}" ] || bad="${held}"
[ "${bad}" -le "${held}" ] || bad="${held}"
if [ "${bad}" -ge "${end}" ] || [ "${bad}" -lt "${start}" ]; then
  copy "${start}" "${end}"
  printf 'addr: %8d\n' "${end}" >&2
  finish "${end}"
  exit 0
fi
copy "${start}" "${bad}"
if [ "${noerror}" = n ]; then
  printf 'readcd: Input/output error. Cannot read source disk\n' >&2
  finish "${bad}"
  exit 255
fi
lba="${bad}"
while [ "${lba}" -lt "${end}" ] && unreadable "${lba}"; do
  printf 'readcd: Input/output error. Error on sector %d not corrected. Total of %d errors.\n' "${lba}" $((lba - bad + 1)) >&2
  dd if=/dev/zero bs="${record}" count=1 2>/dev/null | emit
  lba=$((lba + 1))
done
copy "${lba}" "${end}"
printf 'addr: %8d\n' "${end}" >&2
finish "${end}"
exit 0
