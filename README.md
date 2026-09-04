# XPlay

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/xplay-icon-dark.svg">
  <img src="XPlay/Assets.xcassets/XPlayIcon.imageset/XPlayIcon.svg" width="105" height="90" alt="XPlay icon">
</picture>

XPlay is a macOS menu bar app for building and launching Xcode projects without
keeping Xcode open.

XPlay displays its X-and-Play icon in the menu bar and shows three animated dots
beside it while building and launching a configuration. The project editor adds an `.xcworkspace`, discovers
its schemes, and lets the developer enable multiple schemes with a separate destination
for each one. The initial destination support covers the current Mac and installed iOS
Simulators; physical iOS devices are intentionally excluded.

Right-clicking the icon shows the enabled schemes and their selected destinations,
saved XPlay Projects, and global settings. **Accept Macros** is global, defaults to off,
and requires confirmation before XPlay adds `-skipMacroValidation` to builds. One enabled
scheme is selected for Play per XPlay Project. Choosing a scheme or one of its destinations
in the status menu makes it active, and a left click builds and launches that selection.
Every configuration has its own build log. Existing `.xcodeproj` records remain readable
for migration.

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
