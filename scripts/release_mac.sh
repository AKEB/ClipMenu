#!/usr/bin/env bash
# Build, sign, notarize, and package ClipMenu for distribution.
#
# Requires local notarization credentials in ClipMenu/.env (see .env.example).
#
# Usage:
#   ./scripts/release_mac.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="ClipMenu"
CONFIGURATION="Release"
ARCHIVE_PATH="$ROOT_DIR/build/ClipMenu.xcarchive"
EXPORT_DIR="$ROOT_DIR/build/export"
APP_NAME="ClipMenu.app"
DIST_DIR="$ROOT_DIR/dist"
BUNDLE_ID="app.eetr.ClipMenu"
TEAM_ID="T3658G5P9V"

load_env_file() {
	local env_file="$1"
	[[ -f "$env_file" ]] || return 1
	LOADED_ENV_DIR="$(cd "$(dirname "$env_file")" && pwd)"
	set -a
	# shellcheck disable=SC1090
	source "$env_file"
	set +a
	return 0
}

resolve_env() {
	LOADED_ENV_DIR="$ROOT_DIR"
	if load_env_file "$ROOT_DIR/.env"; then
		return
	fi

	echo "Missing notarization credentials."
	echo "Copy .env.example to .env and place your App Store Connect API key at key.p8"
	exit 1
}

resolve_sign_identity() {
	if [[ -n "${MAC_SIGN_IDENTITY:-}" ]]; then
		echo "$MAC_SIGN_IDENTITY"
		return
	fi

	security find-identity -v -p codesigning \
		| awk -F'"' '/Developer ID Application:/ { print $2; exit }'
}

resolve_apple_api_key_path() {
	local key_value="${APPLE_API_KEY:-}"
	if [[ -z "$key_value" ]]; then
		echo ""
		return
	fi

	if [[ "$key_value" == *"BEGIN PRIVATE KEY"* ]]; then
		local tmp_key
		tmp_key="$(mktemp "${TMPDIR:-/tmp}/clipmenu-notarize.XXXXXX")"
		printf '%s\n' "$key_value" >"$tmp_key"
		chmod 600 "$tmp_key"
		echo "$tmp_key"
		return
	fi

	if [[ "$key_value" = /* ]]; then
		echo "$key_value"
	elif [[ -n "${LOADED_ENV_DIR:-}" ]]; then
		echo "$LOADED_ENV_DIR/$key_value"
	else
		echo "$ROOT_DIR/$key_value"
	fi
}

require_notary_credentials() {
	: "${APPLE_API_KEY_ID:?Missing APPLE_API_KEY_ID}"
	: "${APPLE_API_ISSUER:?Missing APPLE_API_ISSUER}"

	APPLE_API_KEY_PATH="$(resolve_apple_api_key_path)"
	if [[ -z "$APPLE_API_KEY_PATH" || ! -f "$APPLE_API_KEY_PATH" ]]; then
		echo "APPLE_API_KEY must point to an existing .p8 key file (or contain PEM content)."
		exit 1
	fi
}

generate_project() {
	if command -v xcodegen >/dev/null 2>&1; then
		xcodegen generate
	fi
}

archive_app() {
	rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
	mkdir -p "$ROOT_DIR/build"

	xcodebuild archive \
		-project ClipMenu.xcodeproj \
		-scheme "$SCHEME" \
		-configuration "$CONFIGURATION" \
		-archivePath "$ARCHIVE_PATH" \
		-derivedDataPath "$ROOT_DIR/.build/DerivedDataRelease" \
		DEVELOPMENT_TEAM="$TEAM_ID" \
		CODE_SIGN_STYLE=Automatic
}

export_app() {
	xcodebuild -exportArchive \
		-archivePath "$ARCHIVE_PATH" \
		-exportPath "$EXPORT_DIR" \
		-exportOptionsPlist "$ROOT_DIR/ExportOptions.plist"
}

notarize_path() {
	local target="$1"
	echo "[notarytool] submit $target"
	xcrun notarytool submit "$target" \
		--key "$APPLE_API_KEY_PATH" \
		--key-id "$APPLE_API_KEY_ID" \
		--issuer "$APPLE_API_ISSUER" \
		--wait
}

notarize_app_bundle() {
	local app_path="$1"
	local zip_path="$ROOT_DIR/build/ClipMenu-notarize.zip"
	rm -f "$zip_path"
	ditto -c -k --keepParent "$app_path" "$zip_path"
	notarize_path "$zip_path"
	rm -f "$zip_path"
}

staple_path() {
	echo "[stapler] $1"
	xcrun stapler staple "$1"
}

verify_artifact() {
	local target="$1"
	echo "[verify] codesign $target"
	codesign --verify --deep --strict --verbose=2 "$target"
	echo "[verify] stapler $target"
	xcrun stapler validate "$target"
}

create_dmg() {
	local app_path="$1"
	local version
	version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
	local dmg_staging="$ROOT_DIR/build/dmg"
	local dmg_path="$DIST_DIR/ClipMenu-${version}.dmg"
	local dmg_alias="$DIST_DIR/ClipMenu.dmg"

	rm -rf "$dmg_staging"
	mkdir -p "$dmg_staging" "$DIST_DIR"
	cp -R "$app_path" "$dmg_staging/"
	ln -s /Applications "$dmg_staging/Applications"

	rm -f "$dmg_path" "$dmg_alias"
	hdiutil create \
		-volname "ClipMenu" \
		-srcfolder "$dmg_staging" \
		-ov \
		-format UDZO \
		"$dmg_path"

	ln -sf "$(basename "$dmg_path")" "$dmg_alias"
	echo "$dmg_path"
}

main() {
	if [[ "$(uname -s)" != "Darwin" ]]; then
		echo "This script must run on macOS."
		exit 1
	fi

	resolve_env
	require_notary_credentials

	local identity
	identity="$(resolve_sign_identity)"
	if [[ -z "$identity" ]]; then
		echo "No Developer ID Application signing identity found in keychain."
		exit 1
	fi
	echo "Signing identity: $identity"

	generate_project
	archive_app
	export_app

	local app_path="$EXPORT_DIR/$APP_NAME"
	if [[ ! -d "$app_path" ]]; then
		echo "Exported app not found: $app_path"
		exit 1
	fi

	local exported_bundle_id
	exported_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
	if [[ "$exported_bundle_id" != "$BUNDLE_ID" ]]; then
		echo "Unexpected bundle id: $exported_bundle_id (expected $BUNDLE_ID)"
		exit 1
	fi

	notarize_app_bundle "$app_path"
	staple_path "$app_path"
	verify_artifact "$app_path"

	local dmg_path
	dmg_path="$(create_dmg "$app_path")"

	echo "[sign] $dmg_path"
	codesign --force --sign "$identity" --timestamp "$dmg_path"
	notarize_path "$dmg_path"
	staple_path "$dmg_path"
	verify_artifact "$dmg_path"

	echo
	echo "Release complete:"
	echo "  App: $app_path"
	echo "  DMG: $dmg_path"
	echo
	echo "Install to /Applications/ClipMenu.app so Accessibility permission stays stable across updates."
}

main "$@"
