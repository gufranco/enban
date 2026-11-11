#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_drive_read() {
  case "$(disk_os)" in
  Darwin)
    disk_error "reading a drive is not supported on macOS yet, so ${2:-info} stops here."
    return 2
    ;;
  *) ;;
  esac
  if ! disk_dd_toc="$(xorriso -outdev "$1" -toc 2>/dev/null)" ||
    ! disk_dd_speeds="$(xorriso -outdev "$1" -list_speeds 2>/dev/null)"; then
    disk_error "unable to read the drive $1."
    return 1
  fi
  DISK_DRIVE="$1"
  disk_drive_fields "${disk_dd_toc}"
  DISK_DRIVE_SPEEDS="$(disk_drive_speed_list "${disk_dd_speeds}")"
}

disk_drive_fields() {
  disk_df_lines="$(printf '%s\n' "$1" | awk '
    /^Drive type   : / { split($0, part, "\047"); vendor = part[2]; product = part[4]; revision = part[6] }
    /^Media current: / {
      profile = substr($0, 16)
      if (match(profile, / \([0-9a-f][0-9a-f][0-9a-f][0-9a-f]h\)$/)) {
        code = substr(profile, RSTART + 2, 4)
        profile = substr(profile, 1, RSTART - 1)
      }
    }
    /^Media status : / { status = substr($0, 16) }
    /^Media blocks : / { readable = $4; free = $7 }
    /^Media summary: / { sessions = $3; data = $5 }
    END {
      if (status == "is blank") state = "blank"
      else if (status ~ /is appendable/) state = "appendable"
      else if (status ~ /is closed/) state = "closed"
      else if (status == "is not present") state = "empty"
      else state = "unreadable"
      printf "%s\n%s\n%s\n%s\n%s\n%s\n%d\n%d\n%d\n%d\n", vendor, product, revision, profile, code, state, sessions, data, free, readable
    }')"
  disk_drive_assign <<EOF
${disk_df_lines}
EOF
}

disk_drive_assign() {
  read -r DISK_DRIVE_VENDOR
  read -r DISK_DRIVE_PRODUCT
  read -r DISK_DRIVE_REVISION
  read -r DISK_DRIVE_PROFILE
  read -r DISK_DRIVE_CODE
  read -r DISK_DRIVE_STATUS
  read -r DISK_DRIVE_SESSIONS
  read -r DISK_DRIVE_DATA
  read -r DISK_DRIVE_FREE
  read -r DISK_DRIVE_READABLE
}

disk_drive_speed_list() {
  printf '%s\n' "$1" | awk '/^Write speed  : / { k = $4; x = $6; sub(/k$/, "", k); sub(/x.*$/, "", x); print k * 1000, x }'
}

disk_drive_json() {
  disk_dj_speeds="$(printf '%s\n' "${DISK_DRIVE_SPEEDS}" | awk 'NF { out = out (out == "" ? "" : ",") "{\"bytes_per_second\":" $1 ",\"x\":" $2 "}" } END { print out }')"
  disk_dj_drive="$(disk_json_string "${DISK_DRIVE}")"
  disk_dj_vendor="$(disk_json_string "${DISK_DRIVE_VENDOR}")"
  disk_dj_product="$(disk_json_string "${DISK_DRIVE_PRODUCT}")"
  disk_dj_revision="$(disk_json_string "${DISK_DRIVE_REVISION}")"
  disk_dj_profile="$(disk_json_string "${DISK_DRIVE_PROFILE}")"
  disk_dj_code="$(disk_json_string "${DISK_DRIVE_CODE}")"
  printf '{"drive":%s,"vendor":%s,"product":%s,"revision":%s,"profile":%s,"profile_code":%s,"status":"%s",' \
    "${disk_dj_drive}" "${disk_dj_vendor}" "${disk_dj_product}" "${disk_dj_revision}" \
    "${disk_dj_profile}" "${disk_dj_code}" "${DISK_DRIVE_STATUS}"
  printf '"sessions":%s,"data_sectors":%s,"free_sectors":%s,"write_speeds":[%s]}\n' \
    "${DISK_DRIVE_SESSIONS}" "${DISK_DRIVE_DATA}" "${DISK_DRIVE_FREE}" "${disk_dj_speeds}"
}

disk_drive_free_text() {
  awk -v s="${DISK_DRIVE_FREE}" 'BEGIN { printf "%.1f GB\n", s * 2048 / 1000000000 }'
}

disk_drive_speed_text() {
  printf '%s\n' "${DISK_DRIVE_SPEEDS}" | awk 'NF { out = out (out == "" ? "" : ", ") $2 "x" } END { print (out == "" ? "none reported" : out) }'
}

disk_drive_short_profile() {
  printf '%s\n' "${DISK_DRIVE_PROFILE}" | awk '{ name = $1; sub(/,$/, "", name); print name }'
}

disk_drive_rows() {
  disk_dr_free="$(disk_drive_free_text)"
  disk_dr_speeds="$(disk_drive_speed_text)"
  printf 'Drive\t%s, %s %s %s\n' "${DISK_DRIVE}" "${DISK_DRIVE_VENDOR}" "${DISK_DRIVE_PRODUCT}" "${DISK_DRIVE_REVISION}"
  printf 'Disc\t%s, %s\n' "${DISK_DRIVE_PROFILE}" "${DISK_DRIVE_STATUS}"
  printf 'Sessions\t%s, %s data sectors\n' "${DISK_DRIVE_SESSIONS}" "${DISK_DRIVE_DATA}"
  printf 'Free\t%s sectors, %s\n' "${DISK_DRIVE_FREE}" "${disk_dr_free}"
  printf 'Speeds\t%s\n' "${disk_dr_speeds}"
}

disk_drive_report() {
  disk_drive_read "$1" || return 1
  if [ "${DISK_JSON}" = y ]; then
    disk_drive_json
    return 0
  fi
  if disk_ui_out; then
    {
      printf 'Field\tValue\n'
      disk_drive_rows
    } | disk_ui_table
    return 0
  fi
  disk_drive_rows | awk -F '\t' '{ printf "%-10s%s\n", $1, $2 }'
}
