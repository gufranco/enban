#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_mac_drive() {
  case "$1" in
  IO*Services | IO*Services/[0-9]*) return 0 ;;
  *) return 1 ;;
  esac
}

disk_mac_ready() {
  for disk_my_tool in cdrecord readcd; do
    command -v "${disk_my_tool}" >/dev/null 2>&1 && continue
    disk_error "a drive named $1 needs cdrecord and readcd from cdrtools. install cdrtools and try again."
    return 1
  done
}

disk_mac_read() {
  disk_mac_ready "$1" || return 1
  if ! disk_mr_lines="$(disk_mac_lines "$1")"; then
    disk_error "unable to read the drive $1."
    return 1
  fi
  DISK_DRIVE="$1"
  disk_drive_fields "${disk_mr_lines}"
  DISK_DRIVE_SPEEDS="$(disk_drive_speed_list "${disk_mr_lines}")"
  DISK_DRIVE_MEDIA="$(disk_drive_media_list "${disk_mr_lines}")"
}

disk_mac_lines() {
  disk_ml_cap="$(cdrecord "dev=$1" -prcap 2>/dev/null)" || return 1
  disk_ml_status=0
  disk_ml_info="$(cdrecord "dev=$1" -minfo 2>&1)" || disk_ml_status=1
  case "${disk_ml_status}:${disk_ml_info}" in
  0:*) : ;;
  *"No disk / Wrong disk!"*) disk_ml_info="no disc" ;;
  *) return 1 ;;
  esac
  printf '%s\n@@minfo@@\n%s\n' "${disk_ml_cap}" "${disk_ml_info}" | disk_mac_translate
}

disk_mac_translate() {
  awk '
    function value(s) { sub(/^[^:]*: */, "", s); sub(/ +$/, "", s); return s }
    function quoted(s,   part) { split(s, part, "\047"); sub(/ +$/, "", part[2]); return part[2] }
    function speed(s,   t, i, n) {
      gsub(/[(),:]/, " ", s)
      n = split(s, t, " ")
      for (i = 1; i <= n; i++) {
        if (t[i] == "kB/s") kb[count] = t[i - 1]
        if (t[i] == "CD") cdx[count] = t[i + 1] + 0
        if (t[i] == "DVD") dvdx[count] = t[i + 1] + 0
        if (t[i] == "BD") bdx[count] = t[i + 1] + 0
      }
    }
    BEGIN {
      split("CD-ROM:0008 CD-R:0009 CD-RW:000a DVD-ROM:0010 DVD-RAM:0012 BD-ROM:0040 BD-RE:0043 DVD+RW:001a DVD+R:001b DVD+RW/DL:002a DVD+R/DL:002b", pair, " ")
      for (i in pair) { split(pair[i], kv, ":"); code[kv[1]] = kv[2] }
      code["DVD-R sequential recording"] = "0011"
      code["DVD-RW restricted overwrite"] = "0013"
      code["DVD-RW sequential recording"] = "0014"
      code["DVD-R/DL sequential recording"] = "0015"
      code["DVD-R/DL layer jump recording"] = "0016"
      code["BD-R sequential recording"] = "0041"
      code["BD-R random recording"] = "0042"
      lead = 0; free = 0; sessions = 0; count = 0; profiles = 0
    }
    /^@@minfo@@$/ { info = 1; next }
    !info && /^Vendor_info    : / { vendor = quoted($0) }
    !info && /^Identifikation : / { product = quoted($0) }
    !info && /^Revision       : / { revision = quoted($0) }
    !info && /Write speed # [0-9]+:/ { count++; speed($0) }
    !info && /^Profile: / {
      name = substr($0, 10)
      now = sub(/ \(current\)$/, "", name)
      sub(/ +$/, "", name)
      profiles++; pname[profiles] = name; pnow[profiles] = now
    }
    info && /^no disc$/ { absent = 1 }
    info && /^Mounted media class:/ { class = value($0) }
    info && /^Mounted media type:/ { type = value($0) }
    info && /^disk status:/ { disk = value($0) }
    info && /^number of sessions:/ { sessions = value($0) + 0 }
    info && /^Last session leadout start address:/ { lead = value($0) + 0 }
    info && /^Remaining writable size:/ { free = value($0) + 0 }
    END {
      printf "Drive type   : vendor \047%s\047 product \047%s\047 revision \047%s\047\n", vendor, product, revision
      if (type != "") printf "Media current: %s%s\n", type, (type in code ? " (" code[type] "h)" : "")
      if (absent) state = "is not present"
      else if (disk == "empty") { state = "is blank"; sessions = 0 }
      else if (disk == "incomplete/appendable") { state = "is written , is appendable"; sessions = sessions - 1 }
      else if (disk == "complete") state = "is written , is closed"
      else state = "is unsuitable"
      printf "Media status : %s\n", state
      printf "Media blocks : %d readable , %d writable , %d overall\n", lead, free, lead + free
      printf "Media summary: %d sessions, %d data blocks, 0 data, 0 free\n", sessions, lead
      for (i = 1; i <= count; i++) {
        x = dvdx[i]
        if (class == "CD") x = cdx[i]
        if (class == "BD") x = bdx[i]
        printf "Write speed  : %dk , %dx\n", kb[i], x
      }
      for (i = 1; i <= profiles; i++) {
        p = pname[i]
        printf "Profile      : 0x%s (%s)%s\n", (p in code ? code[p] : "0000"), p, (pnow[i] ? " (current)" : "")
      }
    }'
}

disk_mac_dd() {
  disk_md_skip=0
  disk_md_count=0
  disk_md_out=-
  disk_md_noerror=n
  for disk_md_arg in "$@"; do
    case "${disk_md_arg}" in
    skip=*) disk_md_skip="${disk_md_arg#skip=}" ;;
    count=*) disk_md_count="${disk_md_arg#count=}" ;;
    of=*) disk_md_out="${disk_md_arg#of=}" ;;
    conv=*noerror*) disk_md_noerror=y ;;
    *) : ;;
    esac
  done
  set -- "dev=${DISK_DRIVE}" "f=${disk_md_out}" "sectors=${disk_md_skip}-$((disk_md_skip + disk_md_count))"
  [ "${disk_md_noerror}" = n ] || set -- "$@" -noerror retries=0
  [ -z "${DISK_MAC_SPEED}" ] || set -- "$@" "speed=${DISK_MAC_SPEED}"
  disk_md_log="$(mktemp "${TMPDIR:-/tmp}/enban-readcd.XXXXXX")" || return 1
  disk_md_status=0
  readcd "$@" 2>"${disk_md_log}" || disk_md_status=1
  disk_mac_summary "${disk_md_log}" >&2
  rm -f "${disk_md_log}"
  return "${disk_md_status}"
}

disk_mac_summary() {
  tr '\r' '\n' <"$1" | awk -v drive="${DISK_DRIVE}" '
    /Read [0-9.]+ kB at / { kb = $0; sub(/.*Read /, "", kb); sub(/ kB.*/, "", kb) }
    /Time total: / { seconds = $0; sub(/.*Time total: /, "", seconds); sub(/sec.*/, "", seconds) }
    /not corrected/ { bad++ }
    END {
      n = int(kb / 2 + 0.25)
      printf "%d+0 records in\n%d+0 records out\n%d bytes copied, %s s\n", n, n, n * 2048, (seconds == "" ? "0" : seconds)
      for (i = 0; i < bad; i++) printf "dd: error reading \047%s\047: Input/output error\n", drive
    }'
}
