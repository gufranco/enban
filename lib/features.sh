#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_features_read() {
  disk_gr_device="$(disk_raw_device)"
  disk_raw_send -r 65530 -o "$1" "${disk_gr_device}" 46 00 00 00 00 00 00 ff fa 00
}

disk_features_list() {
  od -An -tu1 -v "$1" 2>/dev/null | awk '
    BEGIN {
      split("0000 Profile list|0001 Core|0002 Morphing|0003 Removable medium|0004 Write protect|0010 Random readable|001d Multi-read|001e CD read|001f DVD read|0020 Random writable|0021 Incremental streaming writable|0022 Sector erasable|0023 Formattable|0024 Hardware defect management|0025 Write once|0026 Restricted overwrite|0027 CD-RW CAV write|0028 MRW|0029 Enhanced defect reporting|002a DVD+RW|002b DVD+R|002c Rigid restricted overwrite|002d CD track at once|002e CD mastering|002f DVD-R and DVD-RW write|0033 Layer jump recording|0034 Layer jump rigid restricted overwrite|0035 Stop long operation|0037 CD-RW media write support|0038 BD-R pseudo-overwrite|003a DVD+RW dual layer|003b DVD+R dual layer|0040 BD read|0041 BD write|0042 Timely safe recording|0050 HD DVD read|0051 HD DVD write|0080 Hybrid disc|0100 Power management|0101 SMART|0102 Embedded changer|0103 CD audio external play|0104 Microcode upgrade|0105 Timeout|0106 DVD CSS|0107 Real time streaming|0108 Drive serial number|0109 Media serial number|010a Disc control blocks|010b DVD CPRM|010c Firmware information|010d AACS|010e DVD CSS managed recording|0110 VCPS|0113 SecurDisc|0142 OSSC", known, "|")
      for (i in known) name[substr(known[i], 1, 4)] = substr(known[i], 6)
    }
    { for (i = 1; i <= NF; i++) b[n++] = $i }
    END {
      if (n < 8) exit
      end = b[0] * 16777216 + b[1] * 65536 + b[2] * 256 + b[3] + 4
      if (end > n) end = n
      for (at = 8; at + 4 <= end; at += 4 + b[at + 3]) {
        code = sprintf("%04x", b[at] * 256 + b[at + 1])
        label = (code in name) ? name[code] : "unknown feature"
        printf "%s\t%s\t%s\n", code, label, (b[at + 2] % 2 == 1 ? "current" : "supported")
      }
    }'
}

disk_features_json() {
  printf '%s\n' "$1" | awk -F '\t' -v drive="$2" '
    function quote(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
    NF { out = out (out == "" ? "" : ",") "{\"code\":\"0x" $1 "\",\"name\":" quote($2) ",\"current\":" ($3 == "current" ? "true" : "false") "}" }
    END { printf "{\"drive\":%s,\"features\":[%s]}\n", quote(drive), out }'
}

disk_features_show() {
  if [ "${DISK_JSON}" = y ]; then
    disk_features_json "$1" "${DISK_DRIVE}"
    return 0
  fi
  if disk_ui_out; then
    {
      printf 'Code\tFeature\tState\n'
      printf '%s\n' "$1" | awk -F '\t' 'NF { printf "0x%s\t%s\t%s\n", $1, $2, $3 }'
    } | disk_ui_table
    return 0
  fi
  printf '%s\n' "$1" | awk -F '\t' 'NF { printf "0x%s  %-40s %s\n", $1, $2, $3 }'
}

disk_features_text() {
  disk_gt_file="$(mktemp "${TMPDIR:-/tmp}/enban-features.XXXXXX")" || return 1
  if ! disk_features_read "${disk_gt_file}"; then
    rm -f "${disk_gt_file}"
    return 1
  fi
  disk_features_list "${disk_gt_file}"
  rm -f "${disk_gt_file}"
}

disk_features_run() {
  disk_raw_ready features || return 1
  disk_gs_list="$(disk_features_text)" || return 1
  if [ -z "${disk_gs_list}" ]; then
    disk_error "${DISK_DRIVE} reported no features."
    return 1
  fi
  disk_features_show "${disk_gs_list}"
}
