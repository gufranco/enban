#!/bin/sh
{ set +x; } 2>/dev/null

state="$1"
shift
log="${state%/*}/sg_raw.log"
printf '%s\n' "$*" >>"${log}"

value() {
  sed -n "s/^$1=//p" "${state}" 2>/dev/null
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
  lba=$(((0x$3 << 24) + (0x$4 << 16) + (0x$5 << 8) + 0x$6))
  {
    printf '\000\377\377\377\377\377\377\377\377\377\377\000'
    printf '\000\002\000\001'
    dd if="${device}" bs=2048 skip="${lba}" count=1 2>/dev/null
    head -c 288 /dev/zero
    [ "${request}" -ne 2448 ] || subchannel "${lba}"
  } >"${out}"
  [ "${request}" -gt 0 ] || exit 1
  ;;
*) : ;;
esac
exit 0
