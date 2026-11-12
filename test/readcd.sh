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
for arg in "$@"; do
  case "${arg}" in
  f=*) file="${arg#f=}" ;;
  sectors=*) range="${arg#sectors=}" ;;
  -noerror) noerror=y ;;
  *) : ;;
  esac
done
start="${range%-*}"
end="${range#*-}"
backing="$(value backing)"
bad="$(value bad)"
size="$(wc -c <"${backing}")"
held=$((size / 2048))
[ "${file}" = - ] || : >"${file}"

emit() {
  if [ "${file}" = - ]; then
    cat
  else
    cat >>"${file}"
  fi
}

copy() {
  [ "$2" -gt "$1" ] || return 0
  dd if="${backing}" bs=2048 skip="$1" count=$(($2 - $1)) 2>/dev/null | emit
}

finish() {
  printf 'Time total: 0.250sec\n' >&2
  printf 'Read %d.00 kB at 1024.0 kB/sec.\n' $((($1 - start) * 2)) >&2
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
unreadable() {
  [ "$1" -ge "${held}" ] || [ "$1" -eq "${bad}" ]
}

lba="${bad}"
while [ "${lba}" -lt "${end}" ] && unreadable "${lba}"; do
  printf 'readcd: Input/output error. Error on sector %d not corrected. Total of %d errors.\n' "${lba}" $((lba - bad + 1)) >&2
  dd if=/dev/zero bs=2048 count=1 2>/dev/null | emit
  lba=$((lba + 1))
done
copy "${lba}" "${end}"
printf 'addr: %8d\n' "${end}" >&2
finish "${end}"
exit 0
