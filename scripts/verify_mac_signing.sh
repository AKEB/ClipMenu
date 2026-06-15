#!/usr/bin/env bash
# Verify ClipMenu macOS artifacts are signed and notarization tickets are stapled.
#
# Usage:
#   ./scripts/verify_mac_signing.sh dist/ClipMenu.dmg build/export/ClipMenu.app

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "This script must run on macOS."
	exit 1
fi

if [[ $# -eq 0 ]]; then
	echo "Pass artifact paths (.app/.dmg) as arguments."
	exit 1
fi

verify_one() {
	local target="$1"
	local check_path="$target"

	if [[ ! -e "$target" ]]; then
		echo "=== $target ==="
		echo "status: FAIL (file not found)"
		return 1
	fi

	if [[ "$target" == *.zip ]]; then
		local tmp_dir
		tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/clipmenu-verify.XXXXXX")"
		ditto -x -k "$target" "$tmp_dir"
		check_path="$(find "$tmp_dir" -maxdepth 1 -name '*.app' -print -quit)"
		if [[ -z "$check_path" ]]; then
			echo "=== $target ==="
			echo "status: FAIL (no .app in zip)"
			rm -rf "$tmp_dir"
			return 1
		fi
	fi

	local codesign_ok=0
	local stapler_ok=0

	echo "=== $target ==="
	if codesign --verify --deep --strict "$check_path" >/dev/null 2>&1; then
		codesign_ok=1
	fi

	if xcrun stapler validate "$check_path" >/dev/null 2>&1; then
		stapler_ok=1
	fi

	echo "codesign: $([[ $codesign_ok -eq 1 ]] && echo OK || echo FAIL)"
	echo "stapler: $([[ $stapler_ok -eq 1 ]] && echo OK || echo FAIL)"
	echo "overall: $([[ $codesign_ok -eq 1 && $stapler_ok -eq 1 ]] && echo PASS || echo FAIL)"

	[[ $codesign_ok -eq 1 && $stapler_ok -eq 1 ]]
}

failed=0
for artifact in "$@"; do
	if ! verify_one "$artifact"; then
		failed=1
	fi
	echo
done

exit "$failed"
