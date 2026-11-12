#!/bin/sh
[ -n "${ZSH_VERSION:-}" ] && emulate sh

DISK_LIB="$(cd "$(dirname "$0")/../lib" && pwd)" || exit 1

# shellcheck source=SCRIPTDIR/../lib/core.sh
. "${DISK_LIB}/core.sh"
# shellcheck source=SCRIPTDIR/../lib/ui.sh
. "${DISK_LIB}/ui.sh"
# shellcheck source=SCRIPTDIR/../lib/cli.sh
. "${DISK_LIB}/cli.sh"
# shellcheck source=SCRIPTDIR/../lib/app.sh
. "${DISK_LIB}/app.sh"
# shellcheck source=SCRIPTDIR/../lib/frame.sh
. "${DISK_LIB}/frame.sh"

# shellcheck source=SCRIPTDIR/../lib/drive.sh
. "${DISK_LIB}/drive.sh"
# shellcheck source=SCRIPTDIR/../lib/write.sh
. "${DISK_LIB}/write.sh"
# shellcheck source=SCRIPTDIR/../lib/write_convert.sh
. "${DISK_LIB}/write_convert.sh"
# shellcheck source=SCRIPTDIR/../lib/read.sh
. "${DISK_LIB}/read.sh"
# shellcheck source=SCRIPTDIR/../lib/read_ccd.sh
. "${DISK_LIB}/read_ccd.sh"
# shellcheck source=SCRIPTDIR/../lib/verify.sh
. "${DISK_LIB}/verify.sh"
# shellcheck source=SCRIPTDIR/../lib/build.sh
. "${DISK_LIB}/build.sh"
# shellcheck source=SCRIPTDIR/../lib/build_ids.sh
. "${DISK_LIB}/build_ids.sh"
# shellcheck source=SCRIPTDIR/../lib/build_boot.sh
. "${DISK_LIB}/build_boot.sh"
# shellcheck source=SCRIPTDIR/../lib/build_video.sh
. "${DISK_LIB}/build_video.sh"
# shellcheck source=SCRIPTDIR/../lib/layer.sh
. "${DISK_LIB}/layer.sh"
# shellcheck source=SCRIPTDIR/../lib/layer_files.sh
. "${DISK_LIB}/layer_files.sh"
# shellcheck source=SCRIPTDIR/../lib/project.sh
. "${DISK_LIB}/project.sh"
# shellcheck source=SCRIPTDIR/../lib/build_bdmv.sh
. "${DISK_LIB}/build_bdmv.sh"
# shellcheck source=SCRIPTDIR/../lib/build_udf.sh
. "${DISK_LIB}/build_udf.sh"
# shellcheck source=SCRIPTDIR/../lib/udf_write.sh
. "${DISK_LIB}/udf_write.sh"
# shellcheck source=SCRIPTDIR/../lib/erase.sh
. "${DISK_LIB}/erase.sh"
# shellcheck source=SCRIPTDIR/../lib/checksum.sh
. "${DISK_LIB}/checksum.sh"
# shellcheck source=SCRIPTDIR/../lib/queue.sh
. "${DISK_LIB}/queue.sh"
# shellcheck source=SCRIPTDIR/../lib/discovery.sh
. "${DISK_LIB}/discovery.sh"
# shellcheck source=SCRIPTDIR/../lib/graph.sh
. "${DISK_LIB}/graph.sh"
# shellcheck source=SCRIPTDIR/../lib/sector.sh
. "${DISK_LIB}/sector.sh"
# shellcheck source=SCRIPTDIR/../lib/cue.sh
. "${DISK_LIB}/cue.sh"
# shellcheck source=SCRIPTDIR/../lib/cue_decode.sh
. "${DISK_LIB}/cue_decode.sh"
# shellcheck source=SCRIPTDIR/../lib/raw.sh
. "${DISK_LIB}/raw.sh"
# shellcheck source=SCRIPTDIR/../lib/tray.sh
. "${DISK_LIB}/tray.sh"
# shellcheck source=SCRIPTDIR/../lib/features.sh
. "${DISK_LIB}/features.sh"
# shellcheck source=SCRIPTDIR/../lib/booktype.sh
. "${DISK_LIB}/booktype.sh"
# shellcheck source=SCRIPTDIR/../lib/audio.sh
. "${DISK_LIB}/audio.sh"
# shellcheck source=SCRIPTDIR/../lib/convert.sh
. "${DISK_LIB}/convert.sh"
# shellcheck source=SCRIPTDIR/../lib/settings.sh
. "${DISK_LIB}/settings.sh"
# shellcheck source=SCRIPTDIR/../lib/settings_tab.sh
. "${DISK_LIB}/settings_tab.sh"
# shellcheck source=SCRIPTDIR/../lib/settings_view.sh
. "${DISK_LIB}/settings_view.sh"
# shellcheck source=SCRIPTDIR/../lib/log.sh
. "${DISK_LIB}/log.sh"
# shellcheck source=SCRIPTDIR/../lib/log_tab.sh
. "${DISK_LIB}/log_tab.sh"
# shellcheck source=SCRIPTDIR/../lib/write_tab.sh
. "${DISK_LIB}/write_tab.sh"
# shellcheck source=SCRIPTDIR/../lib/read_tab.sh
. "${DISK_LIB}/read_tab.sh"
# shellcheck source=SCRIPTDIR/../lib/verify_tab.sh
. "${DISK_LIB}/verify_tab.sh"
# shellcheck source=SCRIPTDIR/../lib/build_tab.sh
. "${DISK_LIB}/build_tab.sh"
# shellcheck source=SCRIPTDIR/../lib/build_view.sh
. "${DISK_LIB}/build_view.sh"
# shellcheck source=SCRIPTDIR/../lib/tools_tab.sh
. "${DISK_LIB}/tools_tab.sh"
# shellcheck source=SCRIPTDIR/../lib/drive_tools.sh
. "${DISK_LIB}/drive_tools.sh"
# shellcheck source=SCRIPTDIR/../lib/queue_tab.sh
. "${DISK_LIB}/queue_tab.sh"
# shellcheck source=SCRIPTDIR/../lib/queue_view.sh
. "${DISK_LIB}/queue_view.sh"
# shellcheck source=SCRIPTDIR/../lib/discovery_tab.sh
. "${DISK_LIB}/discovery_tab.sh"
# shellcheck source=SCRIPTDIR/../lib/job.sh
. "${DISK_LIB}/job.sh"

"$@"
