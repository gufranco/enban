#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_features_read() {
  disk_gr_device="$(disk_raw_device)"
  disk_raw_send -r 65530 -o "$1" "${disk_gr_device}" 46 00 00 00 00 00 00 ff fa 00
}

disk_features_list() {
  od -An -tu1 -v "$1" 2>/dev/null | awk -v names="${DISK_FEATURE_NAMES}" '
    BEGIN {
      split(names, known, "|")
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
  if disk_mac_drive "${DISK_DRIVE}"; then
    disk_mac_features
    return
  fi
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
