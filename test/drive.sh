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

case " $* " in
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
  "${real}" "$@" >"${state}.out" || {
    status="$?"
    cat "${state}.out"
    exit "${status}"
  }
  awk -v name="${name}" -v code="${code}" -v blocks="${blocks}" '
    /^Media current: stdio file/ { printf "Media current: %s (%sh)\n", name, code; next }
    /^Media blocks : / { printf "Media blocks : %d readable , %d writable , %d overall\n", $4, blocks - $4, blocks; next }
    { print }' "${state}.out"
  ;;
esac
