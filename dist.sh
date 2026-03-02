#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -e

_SH_SCRIPTS_DIR="$(cd -- "$(dirname -- "$0")" >/dev/null && pwd -P)"
SH_SCRIPTS_DIR="${SH_SCRIPTS_DIR:-"$_SH_SCRIPTS_DIR"}"
# shellcheck source=/dev/null
. "${SH_SCRIPTS_DIR}/dist-common.sh"

main() {
	parse_args "$@"

	printf 'Package    : %s\n' "$DIST_PKG_NAME"
	printf 'Version    : %s\n' "$DIST_PKG_VERSION"
	printf 'Repo URL   : %s\n' "$DIST_REPO_URL"
	printf 'Build type : %s\n' "$DIST_BUILD_TYPE"
	printf 'Meson args : %s\n\n' "$DIST_BUILD_ARGS"

	printf 'Generating version file\n'
	generate_version_file

	if [ "$DIST_VERSION_ONLY" -eq 1 ]; then
		return
	fi

	cd "$MESON_DIST_ROOT" || sh_error "Could not change to ${MESON_DIST_ROOT}"

	if [ "$DIST_SKIP_DEB" -eq 0 ]; then
		printf 'Generating deb package\n\n'
		generate_deb_pkg
	fi

	printf 'Generating binary distribution\n\n'
	generate_bin_pkg
}

main "$@"
