#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -e

_CONFIG_DEF_CFG_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null && pwd -P)
CONFIG_DEF_CFG_DIR=${CONFIG_DEF_CFG_DIR:-"${_CONFIG_DEF_CFG_DIR}"}

_SH_SCRIPTS_DIR="${CONFIG_DEF_CFG_DIR}/.."
# shellcheck disable=SC2034
SH_SCRIPT_NAME="$(basename "$0")"
# shellcheck source=/dev/null
. "${_SH_SCRIPTS_DIR}/_sh-common.sh"

if [ -n "${CONFIG_PKG_SCRIPTS_DIR}" ]; then
	CONFIG_PKG_CFG_DIR="${CONFIG_PKG_SCRIPTS_DIR}/config"
fi

_config_bool_to_string() {
	if [ "$1" -eq 1 ]; then
		echo "true"
	else
		echo "false"
	fi
}

_config_check_pkgconfig_exists() {
	if ! which pkg-config >/dev/null; then
		sh_error "'pkg-config' is not installed"
	fi
}

_config_check_pkg_exists() {
	if ! pkg-config --exists "$1"; then
		sh_error "Package '$1' not found (using 'pkg-config')"
	fi
}

_config_get_pkgconfig_vars() {
	if [ -z "$1" ]; then
		sh_error "No package specified"
	fi

	_config_pkg_prefix="$(pkg-config --variable=prefix "$1")"
	_config_pkg_lib_dir="$(pkg-config --variable=libdir "$1")"
	_config_pkg_bin_dir="${_config_pkg_prefix}/bin"
	_config_pkg_share_dir="${_config_pkg_prefix}/share/$1"
}

_config_set_pkg_path_vars() {
	if [ "$1" != 'vaccel' ]; then
		_config_get_pkgconfig_vars 'vaccel'

		CONFIG_VACCEL_PREFIX="${_config_pkg_prefix}"
		CONFIG_VACCEL_LIB_DIR="${_config_pkg_lib_dir}"
		CONFIG_VACCEL_BIN_DIR="${_config_pkg_bin_dir}"
		CONFIG_VACCEL_SHARE_DIR="${_config_pkg_share_dir}"

		LD_LIBRARY_PATH="${CONFIG_VACCEL_LIB_DIR}:${LD_LIBRARY_PATH}"
	fi

	if [ -z "$2" ]; then
		_config_get_pkgconfig_vars "$1"

		CONFIG_PKG_PREFIX="${_config_pkg_prefix}"
		CONFIG_PKG_LIB_DIR="${_config_pkg_lib_dir}"
		CONFIG_PKG_BIN_DIR="${_config_pkg_bin_dir}"
		CONFIG_PKG_SHARE_DIR="${_config_pkg_share_dir}"

		LD_LIBRARY_PATH="${CONFIG_PKG_LIB_DIR}:${LD_LIBRARY_PATH}"
	else
		CONFIG_PKG_LIB_DIR="$2/src"
		LD_LIBRARY_PATH="${CONFIG_PKG_LIB_DIR}:${LD_LIBRARY_PATH}"
	fi
}

_config_print_pkg_path_vars() {
	if [ -z "${MESON_BUILD_ROOT}" ]; then
		printf "Package prefix     : %s\n" "${CONFIG_PKG_PREFIX}"
		printf "Package lib dir    : %s\n" "${CONFIG_PKG_LIB_DIR}"
		printf "Package bin dir    : %s\n" "${CONFIG_PKG_BIN_DIR}"
		printf "Package share dir  : %s\n" "${CONFIG_PKG_SHARE_DIR}"
	else
		printf "Package lib dir    : %s\n" "${CONFIG_PKG_LIB_DIR}"
	fi

	if [ "${CONFIG_PKG}" != 'vaccel' ]; then
		printf "vAccel prefix      : %s\n" "${CONFIG_VACCEL_PREFIX}"
		printf "vAccel lib dir     : %s\n" "${CONFIG_VACCEL_LIB_DIR}"
		printf "vAccel bin dir     : %s\n" "${CONFIG_VACCEL_BIN_DIR}"
		printf "vAccel share dir   : %s\n" "${CONFIG_VACCEL_SHARE_DIR}"
	fi
}

_config_set_pkg_override_vars() {
	if [ -n "$1" ]; then
		CONFIG_PKG_VARS_ENV="$1/variables.env"
		if [ -f "${CONFIG_PKG_VARS_ENV}" ]; then
			# shellcheck source=/dev/null
			. "${CONFIG_PKG_VARS_ENV}"
		fi
	fi
}

_config_set_valgrind_cmd() {
	CONFIG_DEF_VALGRIND_SUPP="${CONFIG_DEF_CFG_DIR}/valgrind.supp"
	CONFIG_VALGRIND_CMD="${CONFIG_VALGRIND_CMD} --suppressions=${CONFIG_DEF_VALGRIND_SUPP}"

	pkg_valgrind_supp="${CONFIG_PKG_CFG_DIR}/valgrind.supp"
	if [ -f "${pkg_valgrind_supp}" ]; then
		CONFIG_PKG_VALGRIND_SUPP=${pkg_valgrind_supp}
		CONFIG_VALGRIND_CMD="${CONFIG_VALGRIND_CMD} --suppressions=${CONFIG_PKG_VALGRIND_SUPP}"
	fi
	unset pkg_valgrind_supp
}

_config_set_common_vars() {
	if [ -z "${TERM}" ]; then
		export TERM="linux"
	fi

	if [ "$(getconf LONG_BIT)" -eq 64 ]; then
		CONFIG_ARCH_IS_64BIT=1
	else
		CONFIG_ARCH_IS_64BIT=0
	fi

	if [ "${CONFIG_USE_VALGRIND}" -eq 1 ]; then
		_config_set_valgrind_cmd

		# shellcheck disable=SC2034
		CONFIG_WRAPPER_CMD=${CONFIG_VALGRIND_CMD}
	fi

	export LD_LIBRARY_PATH
	export VACCEL_LOG_LEVEL="${CONFIG_VACCEL_LOG_LEVEL}"
}

_config_print_vars() {
	printf "Arch is 64bit      : %s\n" \
		"$(_config_bool_to_string "${CONFIG_ARCH_IS_64BIT}")"
	printf "Default config dir : %s\n" "${CONFIG_DEF_CFG_DIR}"
	printf "Package            : %s\n" "${CONFIG_PKG}"
	printf "Package config dir : %s\n" "${CONFIG_PKG_CFG_DIR}"

	_config_print_pkg_path_vars

	printf "\n"
}

config_set_env() {
	# shellcheck source=/dev/null
	. "${CONFIG_DEF_CFG_DIR}/variables.env"

	_config_check_pkgconfig_exists

	if [ -z "${CONFIG_PKG}" ]; then
		sh_error "'\$CONFIG_PKG' is not set"
	fi

	if [ -z "${MESON_BUILD_ROOT}" ]; then
		_config_check_pkg_exists "${CONFIG_PKG}"
	fi

	_config_set_pkg_path_vars "${CONFIG_PKG}" "${MESON_BUILD_ROOT}"
	_config_set_pkg_override_vars "${CONFIG_PKG_CFG_DIR}"
	_config_set_common_vars

	_config_print_vars
}

config_set_env "$@"
