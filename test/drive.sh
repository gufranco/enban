#!/bin/sh
{ set +x; } 2>/dev/null

real="$1"
state="$2"
shift 2

value() {
  sed -n "s/^$1=//p" "${state}"
}

code="$(value code)"
name="$(value name)"
blocks="$(value blocks)"
speeds="$(value speeds)"

disc_file() {
  for arg in "$@"; do
    case "${arg}" in
    dev=stdio:*) printf '%s\n' "${arg#dev=stdio:}" ;;
    stdio:*) printf '%s\n' "${arg#stdio:}" ;;
    *) ;;
    esac
  done
}

swap_disc() {
  file="$(disc_file "$@")"
  count=1
  while [ -e "${file}.${count}" ] && [ "${count}" -lt 100 ]; do
    count=$((count + 1))
  done
  cp "${file}" "${file}.${count}"
  : >"${file}"
}

case " $* " in
*" -as cdrecord "*)
  fail_write="$(value fail_write)"
  corrupt="$(value corrupt)"
  slow="$(value slow)"
  file="$(disc_file "$@")"
  printf 'burn=%s\n' "$*" >>"${state}"
  [ "${slow}" != 1 ] || sleep 30
  if [ "${fail_write}" = 1 ]; then
    printf 'xorriso : FAILURE : -as cdrecord: Job could not be performed properly.\n' >&2
    exit 5
  fi
  "${real}" "$@" || exit "$?"
  if [ "${corrupt}" = 1 ]; then
    printf 'X' | dd of="${file}" bs=1 seek=4096 conv=notrunc 2>/dev/null
  fi
  ;;
*" -blank "*)
  fail_blank="$(value fail_blank)"
  slow="$(value slow)"
  [ "${slow}" != 1 ] || sleep 30
  if [ "${fail_blank}" = 1 ]; then
    printf 'xorriso : FAILURE : -blank: Job could not be performed properly.\n' >&2
    exit 5
  fi
  printf '%s\n' "$*" | sed -n 's/.* -blank \([a-z_]*\).*/blanked=\1/p' >>"${state}"
  "${real}" "$@"
  ;;
*" -list_profiles "*)
  profiles="$(value profiles)"
  current="$(value current)"
  [ -n "${profiles}" ] || exec "${real}" "$@"
  # shellcheck disable=SC2086
  printf '%s\n' ${profiles} | awk -v current="${current}" '
    BEGIN {
      split("0009 CD-R|000a CD-RW|0011 DVD-R sequential recording|0013 DVD-RW restricted overwrite|0014 DVD-RW sequential recording|001a DVD+RW|001b DVD+R|0041 BD-R sequential recording|0042 BD-R random recording|0043 BD-RE", rows, "|")
      for (i in rows) { code = substr(rows[i], 1, 4); names[code] = substr(rows[i], 6) }
    }
    { printf "Profile      : 0x%s (%s)%s\n", toupper($1), names[$1], ($1 == current ? " (current)" : "") }'
  ;;
*" -eject all "*)
  fail_eject="$(value fail_eject)"
  [ "${fail_eject}" != 1 ] || exit 5
  "${real}" "$@" || exit "$?"
  swap="$(value swap)"
  [ "${swap}" != 1 ] || swap_disc "$@"
  ;;
*" -list_speeds "*)
  "${real}" "$@" >/dev/null || exit "$?"
  # shellcheck disable=SC2086
  printf '%s\n' ${speeds} | awk '
    NF {
      printf "Write speed  :  %5dk , %4.1fxD\n", $1, $1 * 1000 / 1385000
      if (low == "" || $1 < low) low = $1
      if ($1 > high) high = $1
    }
    END {
      printf "Write speed L:  %5dk , %4.1fxD\n", low, low * 1000 / 1385000
      printf "Write speed H:  %5dk , %4.1fxD\n", high, high * 1000 / 1385000
    }'
  ;;
*)
  out="$(mktemp "${state}.out.XXXXXX")"
  "${real}" "$@" >"${out}" || {
    status="$?"
    cat "${out}"
    rm -f "${out}"
    exit "${status}"
  }
  product="$(value product)"
  if [ "${product}" = file ]; then
    product="$(disc_file "$@")"
    product="${product##*/}"
  fi
  awk -v name="${name}" -v code="${code}" -v blocks="${blocks}" -v product="${product}" '
    /^Media current: stdio file/ { printf "Media current: %s (%sh)\n", name, code; next }
    /^Media summary: / && product != "" { print; printf "Media product: %s , Mitsubishi Kagaku Media Co.\n", product; next }
    /^Media blocks : / { printf "Media blocks : %d readable , %d writable , %d overall\n", $4, blocks - $4, blocks; next }
    { print }' "${out}"
  rm -f "${out}"
  ;;
esac
