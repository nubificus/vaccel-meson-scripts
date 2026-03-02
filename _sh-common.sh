#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -e

_SH_SCRIPTS_DIR="$(cd -- "$(dirname -- "$0")" >/dev/null && pwd -P)"
SH_SCRIPTS_DIR="${SH_SCRIPTS_DIR:-"$_SH_SCRIPTS_DIR"}"
# shellcheck source=/dev/null
. "${SH_SCRIPTS_DIR}/sh-common.sh"
