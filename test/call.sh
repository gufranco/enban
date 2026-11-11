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
# shellcheck source=SCRIPTDIR/../lib/read.sh
. "${DISK_LIB}/read.sh"
# shellcheck source=SCRIPTDIR/../lib/verify.sh
. "${DISK_LIB}/verify.sh"
# shellcheck source=SCRIPTDIR/../lib/build.sh
. "${DISK_LIB}/build.sh"
# shellcheck source=SCRIPTDIR/../lib/erase.sh
. "${DISK_LIB}/erase.sh"
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
# shellcheck source=SCRIPTDIR/../lib/job.sh
. "${DISK_LIB}/job.sh"

"$@"
