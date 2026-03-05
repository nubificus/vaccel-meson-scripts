#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -e

_SH_SCRIPTS_DIR="$(cd -- "$(dirname -- "$0")" >/dev/null && pwd -P)"
SH_SCRIPTS_DIR="${SH_SCRIPTS_DIR:-"$_SH_SCRIPTS_DIR"}"
# shellcheck source=/dev/null
. "${SH_SCRIPTS_DIR}/_sh-common.sh"

if [ -n "$MESON_SUBDIR" ]; then
	_MESON_SOURCE_DIR="${MESON_SOURCE_ROOT}/${MESON_SUBDIR}"
else
	_MESON_SOURCE_DIR="$MESON_SOURCE_ROOT"
fi

SOURCE_DIR_DEFAULT="${_MESON_SOURCE_DIR:-.}"
VERSION_DEFAULT='v0.0.1'

parse_args() {
	short_opts='s:,w,o:'
	long_opts='source-dir:,write,output-dir:,no-dirty'

	if ! getopt=$(getopt -o "$short_opts" --long "$long_opts" \
		-n "$SH_SCRIPT_NAME" -- "$@"); then
		sh_error 'Failed to parse args'
	fi

	eval set -- "$getopt"

	write=0
	output_dir=
	no_dirty=0
	while true; do
		case "$1" in
		'-s' | '--source-dir')
			# Source directory
			[ -z "$2" ] &&
				sh_error "'$1' requires a non-empty string"
			source_dir="$2"
			shift 2
			;;
		'-w' | '--write')
			# Write to file
			write=1
			shift 1
			;;
		'-o' | '--output-dir')
			# Write to file in output directory
			[ ! -d "$(dirname "$2")" ] &&
				sh_error "'$1' directory does not exist"
			write=1
			output_dir="$2"
			shift 2
			;;
		'--no-dirty')
			# Do not append '-dirty' metadata
			no_dirty=1
			shift 1
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

	source_dir="${source_dir:-"$SOURCE_DIR_DEFAULT"}"

	unset short_opts
	unset long_opts
}

generate_version() {
	dirty=

	if git -C "$source_dir" status >/dev/null 2>&1 &&
		[ -e "${source_dir}/.git" ]; then
		if git -C "$source_dir" describe --tags --match "v[0-9]*" \
			--exact-match HEAD >/dev/null 2>&1; then
			version=$(git -C "$source_dir" tag --points-at HEAD |
				grep -E '^v[0-9]' |
				awk '{
					tag = $0
					if (match($0, /\+[^,]*/)) {
					  base = substr($0, 1, RSTART-1)
					  build = substr($0, RSTART+1, RLENGTH-1)
					} else {
					  base = $0
					  build = ""
					}
					print base "," build "," tag
				}' |
				sort -V -t',' -k1,1 -k2,2 |
				tail -1 |
				cut -d',' -f3)
		else
			version=$(git -C "$source_dir" describe \
				--abbrev=8 --tags --match "v[0-9]*" 2>/dev/null |
				sed 's/+[^-]*//' ||
				true)
		fi

		if [ -z "$version" ]; then
			sha=$(git -C "$source_dir" describe --abbrev=8 --always)
			commits=$(git -C "$source_dir" log --oneline | wc -l)
			version="v0.0.1-${commits}-${sha}"

			unset sha
			unset commits
		fi

		if [ "$no_dirty" -eq 0 ]; then
			dirty=$(git -C "$source_dir" diff --quiet ||
				echo '-dirty')
		fi
	fi

	version=$(echo "${version:-"$VERSION_DEFAULT"}${dirty}" |
		sed -e 's/-g/-/' | cut -c 2-)

	unset dirty
}

main() {
	parse_args "$@"

	version_file="${source_dir}/.version"
	if [ -f "$version_file" ]; then
		cat "$version_file"
		exit 0
	fi

	generate_version

	if [ "$write" -eq 0 ]; then
		echo "$version"
		exit 0
	fi

	if [ -z "$output_dir" ]; then
		echo "$version" >"$version_file"
	else
		echo "$version" >"${output_dir}/.version"
	fi
}

main "$@"
