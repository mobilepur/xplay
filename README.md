# XPlay

XPlay is a macOS menu bar app for building and launching Xcode projects without
keeping Xcode open.

This initial prototype displays a Play icon in the menu bar and replaces it with
an animated spinner while a project is building. No project can be configured
yet, so the Play button starts disabled. Project and scheme management will be
added next.

## Requirements

- macOS 15 or later
- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) when regenerating the
  checked-in Xcode project

## Generate the Xcode project

```sh
xcodegen generate
open XPlay.xcodeproj
```

## Test

```sh
xcodebuild test \
  -project XPlay.xcodeproj \
  -scheme XPlay \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/XPlayDerivedData
```

## License

XPlay is available under the [MIT License](LICENSE).
