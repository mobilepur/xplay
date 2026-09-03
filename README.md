# XPlay

XPlay is a macOS menu bar app for building and launching Xcode projects without
keeping Xcode open.

This initial prototype displays a Play icon in the menu bar and replaces it with
an animated spinner while a project is building. Right-clicking the icon opens a
native menu with the current project state, saved projects, and an option to quit
XPlay. The project editor can add `.xcodeproj` bundles through Finder, remove saved
projects, and remembers the current selection. Scheme configuration will be added
next, so left-clicking the Play icon currently has no effect.

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
