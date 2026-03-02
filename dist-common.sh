#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -e

_SH_SCRIPTS_DIR="$(cd -- "$(dirname -- "$0")" >/dev/null && pwd -P)"
SH_SCRIPTS_DIR="${SH_SCRIPTS_DIR:-"$_SH_SCRIPTS_DIR"}"
# shellcheck source=/dev/null
. "${SH_SCRIPTS_DIR}/_sh-common.sh"

DIST_REPO_URL=$(git remote get-url origin |
	sed 's/git@github.com:\(.*\)\.git/https:\/\/github.com\/\1/g')
_DIST_UPSTREAM_CONTACT='vaccel@nubificus.co.uk'
_DIST_DEBFULLNAME='Kostis Papazafeiropoulos'
_DIST_DEBEMAIL='papazof@nubificus.co.uk'

parse_args() {
	short_opts='n:v:t:a:'
	long_opts='pkg-name:,pkg-version:,build-type:,build-arg:,pkg-config-path:'
	long_opts="${long_opts},skip-subprojects,skip-deb,version-only"

	if ! getopt=$(getopt -o "$short_opts" --long "$long_opts" \
		-n "$SH_SCRIPT_NAME" -- "$@"); then
		sh_error 'Failed to parse args'
	fi

	eval set -- "$getopt"

	DIST_BUILD_ARGS=
	DIST_INSTALL_ARGS=
	DIST_SKIP_DEB=0
	DIST_SKIP_SUBPROJECTS=0
	DIST_VERSION_ONLY=0
	while true; do
		case "$1" in
		'-n' | '--pkg-name')
			# Package name
			[ -z "$2" ] &&
				sh_error "'$1' requires a non-empty string"
			DIST_PKG_NAME="$2"
			shift 2
			;;
		'-v' | '--pkg-version')
			# Package version
			[ -z "$2" ] &&
				sh_error "'$1' requires a non-empty string"
			DIST_PKG_VERSION="$2"
			shift 2
			;;
		'-t' | '--build-type')
			# Build type
			[ -z "$2" ] &&
				sh_error "'$1' requires a non-empty string"
			DIST_BUILD_TYPE="$2"
			shift 2
			;;
		'-a' | '--build-arg')
			# Build args
			arg=$(echo "$2" | cut -d'=' -f1)
			value=$(echo "$2" | cut -d'=' -f2-)
			[ -z "${arg}" ] || [ -z "${value}" ] &&
				sh_error "'$1' requires a string of the form 'arg=value'"
			DIST_BUILD_ARGS="${DIST_BUILD_ARGS} -D${arg}=${value}"
			unset arg
			unset value
			shift 2
			;;
		'--pkg-config-path')
			# Pkg-config path
			if [ -n "$2" ]; then
				arg="--pkg-config-path=${2}"
				DIST_BUILD_ARGS="${DIST_BUILD_ARGS} ${arg}"
				unset arg
			fi
			shift 2
			;;
		'--skip-subprojects')
			# Skip subproject installation
			DIST_SKIP_SUBPROJECTS=1
			shift
			;;
		'--skip-deb')
			# Skip deb generation
			# shellcheck disable=SC2034
			DIST_SKIP_DEB=1
			shift
			;;
		'--version-only')
			# Only generate version file
			# shellcheck disable=SC2034
			DIST_VERSION_ONLY=1
			shift
			;;
		--)
			shift
			break
			;;
		*)
			sh_error 'Internal error parsing args'
			;;
		esac
	done

	DIST_BUILD_ARGS="--buildtype=${DIST_BUILD_TYPE} ${DIST_BUILD_ARGS}"
	[ "${DIST_SKIP_SUBPROJECTS}" -eq 1 ] &&
		DIST_INSTALL_ARGS="--skip-subprojects"

	if [ -z "${DIST_PKG_NAME}" ] || [ -z "${DIST_PKG_VERSION}" ] ||
		[ -z "${DIST_BUILD_TYPE}" ]; then
		sh_error 'Package name, version or buildtype was not provided'
	fi

	unset short_opts
	unset long_opts
}

generate_version_file() {
	echo "${DIST_PKG_VERSION}" >"${MESON_PROJECT_DIST_ROOT}/.version"
}

is_vaccel() {
	if [ "${DIST_PKG_NAME}" != "vaccel" ]; then
		[ "${DIST_PKG_NAME#*"vaccel"}" = "${DIST_PKG_NAME}" ] &&
			sh_error "Package name must start with 'vaccel'"
		return 1 # false
	fi
	return 0 # true
}

generate_bin_pkg() {
	bin_name="${DIST_PKG_NAME}_${DIST_PKG_VERSION}"
	bin_tar_name="${bin_name}_$(sh_print_arch).tar.gz"
	bin_prefix="${MESON_PROJECT_DIST_ROOT}/build/${bin_name}"

	rm -rf ../"${bin_tar_name}" build

	if [ -f "${DIST_DEB_PKG_FILE}" ]; then
		mkdir -p "build/${bin_name}"
		dpkg -x "${DIST_DEB_PKG_FILE}" "build/${bin_name}"
	else
		eval meson setup "${DIST_BUILD_ARGS}" \
			--wrap-mode=nodownload \
			--prefix="${bin_prefix}/usr" \
			build
		meson compile -C build
		eval meson install "${DIST_INSTALL_ARGS}" -C build
	fi

	tar cfz ../"${bin_tar_name}" -C build "${bin_name}"
	rm -rf build

	DIST_BIN_PKG_FILE="$(dirname "${MESON_PROJECT_DIST_ROOT}")/${bin_tar_name}"
	printf '\nCreated %s\n\n' "$DIST_BIN_PKG_FILE"

	unset bin_name
	unset bin_tar_name
	unset bin_prefix
}

deb_check_requirements() {
	missing_pkgs=

	for p in 'build-essential' 'dh-make' 'git-buildpackage'; do
		if [ -z "$(dpkg -l | awk "/^ii  $p/")" ]; then
			missing_pkgs="${missing_pkgs} $p"
		fi
	done

	if [ -n "${missing_pkgs}" ]; then
		echo "Not building a deb package: Packages${missing_pkgs} missing"
		unset missing_pkgs
		return 1
	fi

	unset missing_pkgs
	return 0
}

deb_process_rules() {
	printf 'export DEB_LDFLAGS_MAINT_STRIP = -Wl,-Bsymbolic-functions\n' \
		>>debian/rules
	printf 'override_dh_auto_configure:\n\t%s' \
		"dh_auto_configure --buildsystem=meson -- ${DIST_BUILD_ARGS}" \
		>>debian/rules
}

deb_process_copyright() {
	sed -i "s/Upstream-Contact.*/Upstream-Contact: ${_DIST_UPSTREAM_CONTACT}/g" \
		debian/copyright
	sed -i "s/Source.*/Source: $(echo "$DIST_REPO_URL" | sed 's/\//\\\//g')/g" \
		debian/copyright
	perl -0777 -i.bak -spe \
		's|Copyright:.*\n(?:[ \t].*\n)*(?=License:)|Copyright:\n 2020-$year Nubificus Ltd.\n|g' \
		-- \
		-year="$(date +"%Y")" \
		debian/copyright
	sed -i -z -e "s/\n#.*[\n]*//g" debian/copyright
}

deb_process_control() {
	sed -i 's/Homepage.*/Homepage: https:\/\/vaccel.org/g' \
		debian/control
	sed -i 's/Section.*/Section: libs/g' debian/control
	sed -i -z -e \
		's/Description.*/Description: Hardware Acceleration for Serverless Computing/g' \
		debian/control
	sed -i '/^#.*/d' debian/control
	sed -i '/cmake/d' debian/control
	if ! is_vaccel; then
		sed -i -z -e \
			's/\(Depends:\n.*\n\)\(Description\)/\1 vaccel,\n\2/g' \
			debian/control
	fi
}

deb_changelog_add_commits() {
	gbp dch --since="$1" --ignore-branch --release \
		--spawn-editor=never --new-version="$2" \
		--dch-opt='-b' --dch-opt='--check-dirname-level=0' \
		--dch-opt='-p' \
		--git-log='--invert-grep --grep=^Signed-off-by:.*github-actions --grep=^Signed-off-by:.*dependabot --grep=^ci: --grep=^ci(.*):'
}

deb_process_changelog() {
	sed -i '2d;3d' debian/changelog
	tag=$(git describe --abbrev=0 --tags --match 'v[0-9]*' 2>/dev/null)
	tag_diff=$(git describe --abbrev=8 --tags --match 'v[0-9]*' 2>/dev/null)
	orig_commit=$(git rev-parse HEAD)

	for t in $(git tag --sort=v:refname | grep 'v[0-9]*'); do
		cur_version="$(echo "$t" | cut -c 2-)-1"
		git checkout "$t" 1>/dev/null 2>&1
		prev_tag=$(git describe --abbrev=0 --tags --match 'v[0-9]*' \
			--exclude="$t" 2>/dev/null) ||
			prev_tag=$(git rev-list --max-parents=0 HEAD | tail -n 1)
		deb_changelog_add_commits "${prev_tag}" "${cur_version}"
	done

	if [ "${tag}" != "${tag_diff}" ]; then
		git checkout "${orig_commit}" 1>/dev/null 2>&1
		prev_tag=$(git describe --abbrev=0 --tags --match 'v[0-9]*' \
			2>/dev/null) ||
			prev_tag=$(git rev-list --max-parents=0 HEAD | tail -n 1)
		cur_version="${DIST_PKG_VERSION}-1"
		deb_changelog_add_commits "${prev_tag}" "${cur_version}"
	fi

	unset tag
	unset tag_diff
	unset orig_commit
	unset cur_version
	unset prev_tag
}

generate_deb_pkg() {
	! deb_check_requirements && return 0

	rm -f ../*"${DIST_PKG_VERSION}".orig.tar.xz
	rm -rf "${MESON_PROJECT_DIST_ROOT}"/.git*

	export DEBFULLNAME="$_DIST_DEBFULLNAME"
	export DEBEMAIL="$_DIST_DEBEMAIL"

	USER="$(whoami)" \
		dh_make -s -y -c apache \
		-p "${DIST_PKG_NAME}_${DIST_PKG_VERSION}" --createorig

	# debian/rules
	deb_process_rules

	# debian/copyright
	deb_process_copyright

	# debian/control
	deb_process_control

	# debian/changelog
	echo 'Generating changelog'
	cp -r "$MESON_PROJECT_SOURCE_ROOT"/.git* ./
	deb_process_changelog
	rm -rf "$MESON_PROJECT_DIST_ROOT"/.git*

	echo 'Building package'
	rm -rf debian/*.ex debian/*.EX debian/*.docs debian/README*
	dpkg-buildpackage -us -uc
	rm -rf obj-* debian

	deb_dir="$(dirname "$MESON_PROJECT_DIST_ROOT")"
	deb_base_name="${DIST_PKG_NAME}_${DIST_PKG_VERSION}"
	DIST_DEB_PKG_FILE="$(ls "$deb_dir"/"$deb_base_name"*.deb)"
	printf '\nCreated %s\n\n' "$DIST_DEB_PKG_FILE"

	unset DEBFULLNAME
	unset DEBEMAIL
	unset deb_dir
	unset deb_name
}
