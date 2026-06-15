# Build And Release Guide

This repository contains the active Swift/XcodeGen ClipMenu project.

## Prerequisites

```sh
xcode-select -p
brew install xcodegen
```

## Generate Project

Run whenever `project.yml` changes:

```sh
xcodegen generate
```

## Build (Debug)

For local development, keep code signing enabled so macOS Accessibility/TCC
continues to recognize ClipMenu as the same app across rebuilds.

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Debug build
```

## Build (Release)

Release builds are signed with Developer ID team `T3658G5P9V` and bundle id
`app.eetr.ClipMenu`.

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Release build
```

## Release DMG (signed + notarized)

`scripts/release_mac.sh` archives, exports with `developer-id`, notarizes the
app and DMG, staples tickets, and writes artifacts to `dist/`.

Set up local credentials once:

```sh
cp .env.example .env
# place App Store Connect API key next to .env as key.p8
```

Release build:

```sh
chmod +x scripts/release_mac.sh scripts/verify_mac_signing.sh
./scripts/release_mac.sh
```

Verify artifacts:

```sh
./scripts/verify_mac_signing.sh dist/ClipMenu.dmg build/export/ClipMenu.app
```

## Unsigned Build (CI / diagnostics only)

Disabling code signing is useful for CI or quick artifact generation, but those
builds can lose Accessibility approval because TCC treats ad-hoc/unsigned
artifacts as a different app identity.

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Release build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Run From Xcode

1. Open `ClipMenu.xcodeproj`.
2. Select scheme `ClipMenu`.
3. Run with `Debug` configuration.

ClipMenu is a menu bar app (`LSUIElement = YES`), so it does not appear in the Dock while running.

## Accessibility Note

Paste simulation uses CGEvent and requires Accessibility permission:

- System Settings -> Privacy & Security -> Accessibility
- Grant permission to the signed app you actually launch from a stable path
  such as `/Applications/ClipMenu.app` or `dist/ClipMenu.app`, not a transient
  DerivedData copy.
- Keep bundle id `app.eetr.ClipMenu` and install path stable across updates so
  the permission checkbox does not reset.

## Troubleshooting

`xcodegen: command not found`

```sh
brew install xcodegen
```

Code signing errors in local/CI builds

- Confirm `Developer ID Application: ... (T3658G5P9V)` exists:
  `security find-identity -v -p codesigning`
- Regenerate project after `project.yml` edits: `xcodegen generate`

Unsigned CI builds

- Use `CODE_SIGN_IDENTITY=""`
- Use `CODE_SIGNING_REQUIRED=NO`
- Use `CODE_SIGNING_ALLOWED=NO`
