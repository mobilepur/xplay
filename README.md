# XPlay

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/xplay-icon-dark.svg">
  <img src="XPlay/Assets.xcassets/XPlayIcon.imageset/XPlayIcon.svg" width="105" height="90" alt="XPlay icon">
</picture>

XPlay is a macOS menu bar app for building and launching Xcode projects without
keeping Xcode open.

The menu bar appearance is configurable in **Settings → Menu Bar Icon**:

- **XPlay** — the X-and-Play icon (default).
- **Name + Target** — the selected project's name and its Mac, iPhone, or iPad symbol.
- **Name** — the selected project's name.
- **Target** — the selected destination's device symbol.

When the chosen content is unavailable, XPlay falls back to its icon. Long project
names are truncated. Three animated dots appear underneath while a configuration
is building and launching.

The menu shows enabled schemes and their selected destinations, a large **Run Project**
button, saved XPlay Projects, and global settings. The Run Project button builds and launches
the selected configuration; it is disabled during a launch or without an available
destination. **Left Click** and **Right Click** can each be set to **Play** or **Menu**.
The current value appears in gray beside each setting's chevron. By default, left
click starts Play and right click opens the menu. The actions are always paired:
changing either click swaps the other, so one runs the project and the other opens
the menu. The Run Project button uses the XPlay icon. The **About** section links the displayed
version to its GitHub release notes and opens the GitHub issue reporter for problems.

The project editor shows `.xcworkspace` files in a full-height sidebar. Selecting a
workspace drills into its launch configurations beside it, where the developer can
enable schemes and choose a separate destination for each one. The
initial destination support covers the current Mac and installed iOS Simulators;
physical iOS devices are intentionally excluded. One enabled scheme is selected for
Play per XPlay Project. Choosing a scheme or one of its destinations in the status
menu makes it active.

**Accept Macros** is global, defaults to off, and requires confirmation before XPlay
adds `-skipMacroValidation` to builds.
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
