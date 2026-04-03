# Build And Release Guide

This repository currently contains two tracks:

- **Modernized app (active):** Swift + XcodeGen project at repo root.
- **Legacy app (reference):** Objective-C project under `legacy/` with historical release scripts.

---

## Prerequisites

Install required tools:

```sh
xcode-select -p
brew install xcodegen
```

Optional (legacy release path only):

```sh
# Python 2-era tooling used by legacy scripts
python --version
openssl version
hdiutil help >/dev/null
```

---

## Modern App: Generate Project

Regenerate the Xcode project any time `project.yml` changes:

```sh
xcodegen generate
```

Expected output includes:

- `Created project at .../ClipMenu.xcodeproj`

---

## Modern App: Build (Debug)

Use this command for local verification and CI:

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

---

## Modern App: Build (Release)

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Release build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

If you need to archive for distribution later, introduce a dedicated archive/export pipeline once app functionality is complete.

---

## Run From Xcode

1. Open `ClipMenu.xcodeproj`.
2. Select scheme `ClipMenu`.
3. Run with `Debug` configuration.

Because ClipMenu is a menu bar app (`LSUIElement = YES`), it does not appear in the Dock while running.

---

## Accessibility / Automation Notes

Paste simulation uses CGEvent, so at runtime macOS will require Accessibility permission for the app. If paste-related behavior fails, verify permissions in:

- System Settings → Privacy & Security → Accessibility

---

## Legacy Build And Release (Historical)

These scripts are kept for compatibility/reference and still reflect the old Sparkle-based release workflow.

### Legacy packaging script

Creates a DMG from `build/Release/ClipMenu.app` plus docs:

```sh
sh script/deploy.sh
```

### Legacy appcast/release-note generation

Script:

- `script/generate_appcast.py`

Important notes:

- Uses Python 2 style syntax and dependencies (`PyRSS2Gen`, `findertools`).
- Reads version from `Info.plist` (legacy location assumptions).
- Writes output to a hard-coded directory (`/Users/naotaka/Sites/sparkle/`).
- Signs archives with `dsa_priv.pem`.

### Legacy version history HTML generation

```sh
sh script/generate_versionhistories.sh
```

Converts:

- `doc/VersionHistory-en.yaml`
- `doc/VersionHistory-ja.yaml`

---

## Troubleshooting

### `xcodegen: command not found`

Install XcodeGen:

```sh
brew install xcodegen
```

### Build picks up legacy project settings

Ensure you are building the root modern project:

- `ClipMenu.xcodeproj` at repository root (not `legacy/ClipMenu.xcodeproj`)

### Code signing errors in local/CI builds

Use the build flags shown above:

- `CODE_SIGN_IDENTITY=""`
- `CODE_SIGNING_REQUIRED=NO`
- `CODE_SIGNING_ALLOWED=NO`

---

## Recommended Release Direction (Modern App)

Current modern app is still in migration. Until feature-complete:

1. Treat root builds as validation builds.
2. Keep legacy Sparkle release scripts for historical reference only.
3. Add a modern archive/notarization/release pipeline after Phase 2/3 implementation is complete.
