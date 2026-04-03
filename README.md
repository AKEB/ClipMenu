# ClipMenu

ClipMenu is a macOS clipboard manager rebuilt in Swift (SwiftUI + SwiftData).

## Current Stack

- Language: Swift 5.9+
- Platform: macOS 14+
- Build system: XcodeGen (`project.yml`)
- App type: menu bar app (`LSUIElement`)
- Dependency: `KeyboardShortcuts`

## Build

Prerequisites:

```sh
xcode-select -p
brew install xcodegen
```

Generate project:

```sh
xcodegen generate
```

Build (Debug):

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Debug build \
	CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

For detailed commands and troubleshooting, see `BUILD.md`.

## Repository Cleanup Status

- Legacy Objective-C source and historical release tooling were removed from the repository after migration completion.
- Historical Sparkle/appcast release scripts are no longer part of this project.
- Release and documentation flow is now maintained directly in Markdown docs in this repository.

## Distribution Note

If you distribute derived work:

1. Do not use `ClipMenu` as your product name.
2. Follow the MIT license terms.

## License

ClipMenu is available under the MIT license. See `LICENSE` for details.
