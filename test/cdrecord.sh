#!/bin/sh
{ set +x; } 2>/dev/null

state="$1"
shift
log="${state%/*}/cdrecord.log"
printf '%s\n' "$*" >>"${log}"

value() {
  sed -n "s/^$1=//p" "${state}" 2>/dev/null | sed -n '$p'
}

put() {
  grep -v "^$1=" "${state}" >"${state}.new"
  printf '%s=%s\n' "$1" "$2" >>"${state}.new"
  mv -f "${state}.new" "${state}"
}

refuse() {
  printf 'cdrecord: %s\n' "$1" >&2
  exit 255
}

backing="$(value backing)"
vendor="$(value vendor)"
product="$(value product)"
revision="$(value revision)"
class="$(value class)"
type="$(value type)"
status="$(value status)"
sessions="$(value sessions)"
leadout="$(value leadout)"
free="$(value free)"
speeds="$(value speeds)"
profiles="$(value profiles)"
fail_prcap="$(value fail_prcap)"
fail_minfo="$(value fail_minfo)"
fail_blank="$(value fail_blank)"
fail_write="$(value fail_write)"
fail_eject="$(value fail_eject)"
fail_load="$(value fail_load)"
fail_fix="$(value fail_fix)"
features="$(value features)"
total=$((leadout + free))

profile_lines() {
  printf '%s\n' "${profiles}" | tr ';' '\n' | while IFS=: read -r name now; do
    [ -n "${name}" ] || continue
    if [ "${now}" = 1 ]; then
      printf 'Profile: %s (current)\n' "${name}"
    else
      printf 'Profile: %s \n' "${name}"
    fi
  done
}

capabilities() {
  [ "${fail_prcap}" != 1 ] || refuse 'Cannot open SCSI driver.'
  printf "Vendor_info    : '%-8s'\n" "${vendor}"
  printf "Identifikation : '%-16s'\n" "${product}"
  printf "Revision       : '%-4s'\n" "${revision}"
  index=0
  for kb in ${speeds}; do
    printf '  Write speed # %d: %5d kB/s CLV/PCAV (CD %3ux, DVD %2ux, BD %2ux)\n' "${index}" "${kb}" $((kb / 176)) $((kb / 1385)) $((kb / 4495))
    index=$((index + 1))
  done
  printf '\nSupported profiles according to MMC-4 feature list:\n'
  profile_lines
  case " $* " in
  *" -x "*) feature_lines ;;
  *) : ;;
  esac
}

feature_lines() {
  printf '\nSupported features according to MMC-4 feature list:\n'
  for pair in ${features}; do
    if [ "${pair#*:}" = 1 ]; then
      printf "Feature: 0x%s 'Some feature' (current) \n" "${pair%:*}"
    else
      printf "Feature: 0x%s 'Some feature'  \n" "${pair%:*}"
    fi
  done
}

fixate() {
  [ "${fail_fix}" != 1 ] || refuse 'Cannot fixate disk.'
  case " $* " in
  *" -multi "*) put sessions $((sessions + 1)) ;;
  *) put status complete ;;
  esac
}

media() {
  [ "${status}" != none ] || refuse 'No disk / Wrong disk!'
  [ "${fail_minfo}" != 1 ] || refuse 'CD/DVD/BD-Recorder not ready.'
  printf 'Mounted media class:      %s\nMounted media type:       %s\n' "${class}" "${type}"
  printf 'Disk Is not erasable\ndata type:                standard\n'
  printf 'disk status:              %s\nsession status:           %s\n' "${status}" "${status}"
  printf 'number of sessions:       %s\n' "${sessions}"
  printf '\nTrack  Sess Type   Start Addr End Addr   Size\n==============================================\n\n'
  [ "${leadout}" -eq 0 ] || printf 'Last session start address:         0\nLast session leadout start address: %s\n' "${leadout}"
  [ "${free}" -eq 0 ] || printf 'Next writable address:              %s\nRemaining writable size:            %s\n' "${leadout}" "${free}"
}

blank() {
  [ "${fail_blank}" != 1 ] || refuse 'Cannot blank disk, aborting.'
  : >"${backing}"
  put status empty
  put sessions 1
  put leadout 0
  put free "${total}"
}

burn() {
  [ "${fail_write}" != 1 ] || refuse 'A write error occurred.'
  case " $* " in
  *" -dummy "*) exit 0 ;;
  *) : ;;
  esac
  for image in "$@"; do :; done
  if [ "${image}" = - ]; then
    cat >"${backing}"
  else
    cat "${image}" >"${backing}"
  fi
  size="$(wc -c <"${backing}")"
  sectors=$((size / 2048))
  put leadout "${sectors}"
  case " $* " in
  *" -multi "*)
    put status incomplete/appendable
    put sessions 2
    put free $((total - sectors))
    ;;
  *)
    put status complete
    put sessions 1
    put free 0
    ;;
  esac
  printf 'Track 01: Total bytes read/written: %s/%s (%s sectors).\n' "${size}" "${size}" "${sectors}"
}

case " $* " in
*" -prcap "*) capabilities "$@" ;;
*" -fix "*) fixate "$@" ;;
*" -load "* | *" -lock "* | *" -abort "*) [ "${fail_load}" != 1 ] || refuse 'Cannot load media.' ;;
*" -minfo "*) media ;;
*" -dao "* | *" -tao "*) burn "$@" ;;
*" -eject "*) [ "${fail_eject}" != 1 ] || refuse 'Cannot eject.' ;;
*" blank="*) blank ;;
*) : ;;
esac
exit 0
