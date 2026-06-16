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

create_dmg_background() {
	local background_path="$1"
	mkdir -p "$(dirname "$background_path")" "$ROOT_DIR/.build/SwiftModuleCache"

	xcrun swift -module-cache-path "$ROOT_DIR/.build/SwiftModuleCache" - "$background_path" >/dev/null <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let width: CGFloat = 640
let height: CGFloat = 420
let image = NSImage(size: NSSize(width: width, height: height))

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func fillRounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func strokePolyline(_ points: [NSPoint], width: CGFloat, color: NSColor) {
    guard let first = points.first else { return }
    color.setStroke()
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.stroke()
}

image.lockFocus()
NSGradient(
    starting: color(31, 48, 69, 1),
    ending: color(35, 99, 113, 1)
)!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -18)

fillRounded(NSRect(x: 56, y: 84, width: 216, height: 224), radius: 30, color: NSColor(calibratedWhite: 1, alpha: 0.16))
fillRounded(NSRect(x: 368, y: 84, width: 216, height: 224), radius: 30, color: NSColor(calibratedWhite: 1, alpha: 0.16))
fillRounded(NSRect(x: 79, y: 107, width: 170, height: 178), radius: 26, color: NSColor(calibratedWhite: 1, alpha: 0.12))
fillRounded(NSRect(x: 391, y: 107, width: 170, height: 178), radius: 26, color: NSColor(calibratedWhite: 1, alpha: 0.12))

let arrowColor = NSColor(calibratedWhite: 1, alpha: 0.55)
strokePolyline([NSPoint(x: 296, y: 196), NSPoint(x: 345, y: 196)], width: 7, color: arrowColor)
strokePolyline([NSPoint(x: 329, y: 214), NSPoint(x: 348, y: 196), NSPoint(x: 329, y: 178)], width: 7, color: arrowColor)

image.unlockFocus()

let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT
}

configure_dmg_finder() {
	local mount_path="$1"

	osascript >/dev/null <<APPLESCRIPT
set dmgFolder to POSIX file "$mount_path" as alias
set backgroundImage to POSIX file "$mount_path/.background/background.png" as alias

tell application "Finder"
	tell folder dmgFolder
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set bounds of container window to {120, 120, 760, 540}
		set theViewOptions to icon view options of container window
		set arrangement of theViewOptions to not arranged
		set icon size of theViewOptions to 128
		set background picture of theViewOptions to backgroundImage
		set position of item "ClipMenu.app" of container window to {164, 214}
		set position of item "Applications" of container window to {476, 214}
		if exists item ".background" of container window then
			set position of item ".background" of container window to {88, 900}
		end if
		if exists item ".fseventsd" of container window then
			set position of item ".fseventsd" of container window to {210, 900}
		end if
		update without registering applications
		delay 1
		close
	end tell
end tell
APPLESCRIPT
}

create_dmg() {
	local app_path="$1"
	local version
	version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
	local dmg_staging="$ROOT_DIR/build/dmg"
	local dmg_mount="$ROOT_DIR/build/dmg-mount"
	local rw_dmg="$ROOT_DIR/build/ClipMenu-${version}-rw.dmg"
	local dmg_path="$DIST_DIR/ClipMenu-${version}.dmg"
	local dmg_alias="$DIST_DIR/ClipMenu.dmg"
	local volume_name="ClipMenu"
	local background_path="$dmg_staging/.background/background.png"

	rm -rf "$dmg_staging" "$dmg_mount" "$rw_dmg"
	mkdir -p "$dmg_staging" "$DIST_DIR"
	cp -R "$app_path" "$dmg_staging/"
	ln -s /Applications "$dmg_staging/Applications"
	create_dmg_background "$background_path"

	rm -f "$dmg_path" "$dmg_alias"
	hdiutil create \
		-volname "$volume_name" \
		-srcfolder "$dmg_staging" \
		-ov \
		-fs HFS+ \
		-format UDRW \
		"$rw_dmg" >&2

	mkdir -p "$dmg_mount"
	local device
	device="$(hdiutil attach "$rw_dmg" -mountpoint "$dmg_mount" -nobrowse -noverify -noautoopen | awk '/Apple_HFS/ { print $1; exit }')"
	mkdir -p "$dmg_mount/.fseventsd"
	touch "$dmg_mount/.fseventsd/no_log"
	chflags hidden "$dmg_mount/.background" "$dmg_mount/.fseventsd" 2>/dev/null || true
	SetFile -a V "$dmg_mount/.background" "$dmg_mount/.fseventsd" 2>/dev/null || true
	if ! configure_dmg_finder "$dmg_mount"; then
		hdiutil detach "$device" -force >&2 || true
		rm -rf "$dmg_mount" "$rw_dmg"
		return 1
	fi
	sync
	hdiutil detach "$device" >&2

	hdiutil convert "$rw_dmg" \
		-format UDZO \
		-imagekey zlib-level=9 \
		-o "$dmg_path" >&2
	rm -rf "$dmg_mount" "$rw_dmg"

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
	dmg_path="$(create_dmg "$app_path" | awk 'NF { line=$0 } END { print line }')"

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
