#!/bin/sh
{ set +x; } 2>/dev/null

state="$1"
shift
log="${state%/*}/sg_raw.log"
printf '%s\n' "$*" >>"${log}"

value() {
  sed -n "s/^$1=//p" "${state}" 2>/dev/null
}

out=""
request=0
device=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  -o)
    out="$2"
    shift 2
    ;;
  -r)
    request="$2"
    shift 2
    ;;
  -s | -i) shift 2 ;;
  -*) shift ;;
  *)
    device="$1"
    shift
    break
    ;;
  esac
done

fail="$(value raw_fail)"
if [ "${fail}" = 1 ]; then
  printf 'sg_raw: SCSI Status: Check Condition\n' >&2
  exit 5
fi

case "$1" in
51)
  track="$(value last_track)"
  track="${track:-1}"
  {
    head -c 6 /dev/zero
    printf '%b' "$(printf '\\%03o' $((track % 256)))"
    head -c 4 /dev/zero
    printf '%b' "$(printf '\\%03o' $((track / 256)))"
    head -c 22 /dev/zero
  } >"${out}"
  ;;
a4)
  rpc="$(value rpc)"
  printf '%b' "${rpc}" >"${out}"
  ;;
be)
  lba=$(((0x$2 << 24) + (0x$3 << 16) + (0x$4 << 8) + 0x$5))
  {
    printf '\000\377\377\377\377\377\377\377\377\377\377\000'
    printf '\000\002\000\001'
    dd if="${device}" bs=2048 skip="${lba}" count=1 2>/dev/null
    head -c 288 /dev/zero
  } >"${out}"
  [ "${request}" -gt 0 ] || exit 1
  ;;
*) : ;;
esac
exit 0
