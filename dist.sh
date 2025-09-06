#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -e

_SH_SCRIPTS_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null && pwd -P)
# shellcheck disable=SC2034
SH_SCRIPT_NAME=$(basename "$0")
# shellcheck source=/dev/null
. "${_SH_SCRIPTS_DIR}/_sh-common.sh"

REPO_URL=$(git remote get-url origin |
	sed 's/git@github.com:\(.*\)\.git/https:\/\/github.com\/\1/g')
UPFULLNAME='Anastassios Nanos'
UPEMAIL='ananos@nubificus.co.uk'
DEBFULLNAME='Kostis Papazafeiropoulos'
export DEBFULLNAME
DEBEMAIL='papazof@nubificus.co.uk'
export DEBEMAIL

parse_args() {
	short_opts='n:v:t:a:'
	long_opts='pkg-name:,pkg-version:,build-type:,build-arg:,skip-subprojects,skip-deb'

	if ! getopt=$(getopt -o "${short_opts}" --long "${long_opts}" \
		-n "${SCRIPT_NAME}" -- "$@"); then
		sh_error 'Failed to parse args'
	fi

	eval set -- "$getopt"

	build_args=
	install_args=
	skip_deb=0
	skip_subprojects=0
	while true; do
		case "$1" in
		'-n' | '--pkg-name')
			# Package name
			[ -z "$2" ] &&
				sh_error "'$1' requires a non-empty string"
			pkg_name="$2"
			shift 2
			;;
		'-v' | '--pkg-version')
			# Package version
			[ -z "$2" ] &&
				sh_error "'$1' requires a non-empty string"
			pkg_version="$2"
			shift 2
			;;
		'-t' | '--build-type')
			# Build type
			[ -z "$2" ] &&
				sh_error "'$1' requires a non-empty string"
			build_type="$2"
			shift 2
			;;
		'-a' | '--build-arg')
			# Build args
			arg=$(echo "$2" | cut -d'=' -f1)
			value=$(echo "$2" | cut -d'=' -f2-)
			[ -z "${arg}" ] || [ -z "${value}" ] &&
				sh_error "'$1' requires a string of the form 'arg=value'"
			build_args="${build_args} -D${arg}=${value}"
			unset arg
			unset value
			shift 2
			;;
		'--skip-subprojects')
			# Skip subproject installation
			skip_subprojects=1
			shift
			;;
		'--skip-deb')
			# Skip deb generation
			skip_deb=1
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

	build_args="--buildtype=${build_type} ${build_args}"
	[ "${skip_subprojects}" -eq 1 ] && install_args="--skip-subprojects"

	if [ -z "${pkg_name}" ] || [ -z "${pkg_version}" ] ||
		[ -z "${build_type}" ]; then
		sh_error 'Package name, version or buildtype was not provided'
	fi
}

generate_version_file() {
	echo "${pkg_version}" >"${MESON_DIST_ROOT}/.version"
}

is_vaccel() {
	if [ "${pkg_name}" != "vaccel" ]; then
		[ "${pkg_name#*"vaccel"}" = "${pkg_name}" ] &&
			sh_error "Package name must start with 'vaccel'"
		return 1 # false
	fi
	return 0 # true
}

generate_bin_pkg() {
	bin_name="${pkg_name}-${pkg_version}"
	bin_tar_name="${bin_name}-bin.tar.gz"
	bin_prefix="${MESON_DIST_ROOT}/build/${bin_name}"

	rm -rf ../"${bin_tar_name}" build
	eval meson setup "${build_args}" --prefix="${bin_prefix}/usr" build
	meson compile -C build
	eval meson install "${install_args}" -C build
	tar cfz ../"${bin_tar_name}" -C build "${bin_name}"
	rm -rf build

	printf "\n%s\n\n" \
		"Created $(dirname "${MESON_DIST_ROOT}")/${bin_tar_name}"
}

deb_check_requirements() {
	missing_pkgs=
	for p in 'build-essential' 'dh-make' 'git-buildpackage'; do
		if [ -z "$(dpkg -l | awk "/^ii  $p/")" ]; then
			missing_pkgs="${missing_pkgs} $p"
		fi
	done
	if [ -n "${missing_pkgs}" ]; then
		echo "Not building a deb package: Packages ${missing_pkgs} missing"
		return 1
	fi
	return 0
}

deb_process_rules() {
	printf "%s\n" \
		'export DEB_LDFLAGS_MAINT_STRIP = -Wl,-Bsymbolic-functions' \
		>>debian/rules
	printf "%s\n\t%s" 'override_dh_auto_configure:' \
		"dh_auto_configure --buildsystem=meson -- ${build_args}" \
		>>debian/rules
}

deb_process_copyright() {
	sed -i "s/Upstream-Contact.*/Upstream-Contact: ${UPFULLNAME} <${UPEMAIL}>/g" \
		debian/copyright
	sed -i "s/Source.*/Source: $(echo "$REPO_URL" | sed 's/\//\\\//g')/g" \
		debian/copyright
	sed -i -z -e \
		"s/\(Copyright:\)\n[^\n]\+[\n]*[^\n]*\n\(License\)/\1 2020-$(date +"%Y") Nubificus LTD <info@nubificus.co.uk>\n\2/g" \
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
		cur_version="${pkg_version}-1"
		deb_changelog_add_commits "${prev_tag}" "${cur_version}"
	fi
	unset tag
	unset tag_diff
	unset orig_commit
}

generate_deb_pkg() {
	! deb_check_requirements && return 0

	rm -f ../*"${pkg_version}".orig.tar.xz
	rm -rf "${MESON_DIST_ROOT}"/.git*

	USER="$(whoami)" \
		dh_make -s -y -c apache \
		-p "${pkg_name}_${pkg_version}" --createorig

	# debian/rules
	deb_process_rules

	# debian/copyright
	deb_process_copyright

	# debian/control
	deb_process_control

	# debian/changelog
	echo 'Generating changelog'
	cp -r "${MESON_SOURCE_ROOT}"/.git* ./
	deb_process_changelog
	rm -rf "${MESON_DIST_ROOT}"/.git*

	echo 'Building package'
	rm -rf debian/*.ex debian/*.EX debian/*.docs debian/README*
	dpkg-buildpackage -us -uc
	rm -rf obj-* debian

	printf "\n%s\n\n" \
		"Created $(ls "$(dirname "${MESON_DIST_ROOT}")"/"${pkg_name}_${pkg_version}"*.deb)"
}

main() {
	parse_args "$@"

	printf "Package    : %s\n" "${pkg_name}"
	printf "Version    : %s\n" "${pkg_version}"
	printf "Repo URL   : %s\n" "${REPO_URL}"
	printf "Build type : %s\n" "${build_type}"
	printf "Meson args : %s\n\n" "${build_args}"

	generate_version_file

	cd "${MESON_DIST_ROOT}" || sh_error "Could not change to ${MESON_DIST_ROOT}"

	printf "%s\n\n" 'Generating binary distribution'
	generate_bin_pkg

	if [ "${skip_deb}" -eq 0 ]; then
		printf "%s\n\n" 'Generating deb package'
		generate_deb_pkg
	fi
}

main "$@"
