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

"$@"
