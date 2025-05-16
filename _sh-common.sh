#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -e

sh_log_error() {
	error=${1:-'Unknown error'}
	code=${2:-1}
	printf "%s: %s [error %s]\n" \
		"${SH_SCRIPT_NAME}" "${error}" "${code}" \
		>&2
	unset error
	unset code
}

sh_error() {
	error_code=${2:-1}
	sh_log_error "$1" "${error_code}"
	exit "${error_code}"
}
