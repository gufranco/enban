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
      for (k = 0; k < 12; k++) {
        v = q[k]
        for (j = 0; j < 8; j++) { bit[j] = v % 2; v = int(v / 2) }
        for (j = 7; j >= 0; j--) printf "\\0%03o", bit[j] * 64
      }
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
46)
  listed="$(value features)"
  profile="$(value code)"
  escapes="$(printf '%s\n' "${listed}" | awk -v code="${profile}" '
    function put(v) { printf "\\0%03o", v }
    NF {
      count = split($0, list, " ")
      put(0); put(0); put(0); put(4 + 4 * count)
      put(0); put(0); put(int(strtonum_hex(code) / 256)); put(strtonum_hex(code) % 256)
      for (i = 1; i <= count; i++) {
        split(list[i], part, ":")
        value = strtonum_hex(part[1])
        put(int(value / 256)); put(value % 256); put(part[2] == 1 ? 1 : 0); put(0)
      }
    }
    function strtonum_hex(h,   v, k, c) {
      v = 0
      for (k = 1; k <= length(h); k++) { c = index("0123456789abcdef", substr(h, k, 1)) - 1; v = v * 16 + c }
      return v
    }')"
  printf '%b' "${escapes}" >"${out}"
  ;;
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
  count=$(((0x$7 << 16) + (0x$8 << 8) + 0x$9))
  main="${10}"
  sub="${11}"
  bad="$(value bad_lba)"
  index=0
  : >"${out}"
  while [ "${index}" -lt "${count}" ]; do
    at=$((lba + index))
    index=$((index + 1))
    if [ "${at}" = "${bad}" ]; then
      printf 'sg_raw: SCSI Status: Check Condition\n' >&2
      exit 5
    fi
    if [ "${main}" != 00 ]; then
      {
        printf '\000\377\377\377\377\377\377\377\377\377\377\000\000\002\000\001'
        dd if="${device}" bs=2048 skip="${at}" count=1 2>/dev/null
        head -c 288 /dev/zero
      } >>"${out}"
    fi
    [ "${sub}" != 01 ] || subchannel "${at}" >>"${out}"
  done
  flip="$(value flip_after)"
  calls="$(wc -l <"${log}")"
  if [ -n "${flip}" ] && [ "${main}" != 00 ] && [ "${calls}" -gt "${flip}" ]; then
    byte="$(od -An -c -j 20 -N 1 "${out}" | tr -d ' ')"
    mark=X
    [ "${byte}" != X ] || mark=Y
    printf '%s' "${mark}" | dd of="${out}" bs=1 seek=20 conv=notrunc 2>/dev/null
  fi
  [ "${request}" -gt 0 ] || exit 1
  ;;
*) : ;;
esac
exit 0
