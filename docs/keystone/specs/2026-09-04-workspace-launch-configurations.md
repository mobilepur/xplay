# Workspace Launch Configurations

## Goal

Let a developer define an XPlay Project from an Xcode workspace, enable multiple app
schemes, choose one compatible destination for each scheme, and select the configuration
that the Play button builds and launches.

## Audience

Developers who maintain multi-platform Xcode workspaces and want to exercise their
macOS and iOS applications together without keeping Xcode open.

## Approved behavior

### XPlay Projects and workspaces

- One XPlay Project is anchored by one `.xcworkspace` or `.xcodeproj`.
- `Add Project…` opens Finder and accepts either Xcode container type.
- XPlay discovers the workspace's schemes and displays them as a checklist.
- Enabling a scheme creates one launch configuration for that scheme.
- Existing `.xcodeproj` records remain readable without requiring migration to a workspace.

### Destinations

- Each enabled scheme owns its own destination selection.
- The status menu lists every enabled scheme beneath the selected XPlay Project.
- Each scheme has a separate Change button to the right of its destination. It opens
  a destination submenu containing only concrete destinations supported by that scheme,
  while the main menu remains visible. The scheme area independently selects it for Play.
- Exactly one enabled scheme is selected for Play per XPlay Project and is marked with a
  checkmark in the status menu.
- Choosing a scheme for Play, or choosing one of its destinations, persists that scheme
  as the active launch configuration.
- Placeholder destinations such as `Any iOS Simulator Device` are not selectable.
- If exactly one concrete destination is available, XPlay may select it automatically.
- If multiple destinations are available, the developer must choose one explicitly.
- A missing or unavailable saved destination remains visible as unavailable and is not
  silently replaced.

### Launching

- A left-click on the Play icon executes the selected launch configuration for the
  selected XPlay Project.
- A macOS configuration builds and opens its app on the selected Mac destination.
- An iOS Simulator configuration builds, boots the simulator when necessary, installs
  the app, and launches it.
- Completion reports a launch failure for the selected configuration and preserves its
  separate build log.
- The menu bar tooltip and accessibility label name the configuration being launched.

### Global settings

- The status menu contains a `Settings` section.
- `Accept Macros` is a global switch in that section and no longer appears in a project
  row.
- Macro acceptance defaults to off.
- Enabling it requires an explicit warning that validation is skipped for all current
  and future macros in every XPlay Project.
- When enabled, every Xcode build receives `-skipMacroValidation`.
- Existing per-project macro consent is not promoted to global consent automatically.

## UX states

- **Empty:** With no XPlay Project, Play is disabled and the menu directs the developer
  to add a project or workspace.
- **Loading:** Scheme or destination discovery displays an inline loading state without
  hiding already persisted configuration.
- **Incomplete:** An enabled scheme without an available selected destination displays
  `Choose Destination…`; Play remains disabled.
- **Failure:** Discovery and launch errors name the affected workspace or launch
  configuration and provide a recovery action or build log.
- **Unavailable:** A saved destination that disappears is marked unavailable until the
  developer selects a replacement.

## Initial scope

### Included

- Xcode workspaces
- Multiple enabled schemes per XPlay Project
- Per-scheme destination selection
- Current Mac destinations
- iOS Simulator destinations
- One selected launch configuration per XPlay Project
- Global macro acceptance
- Persistence and legacy `.xcodeproj` compatibility

### Excluded

- Physical iPhone and iPad installation or launch
- watchOS, tvOS, visionOS, and remote Mac destinations
- Parallel Xcode builds
- Creating or modifying `.xcworkspace` bundles
- Test-plan execution

## Acceptance criteria

1. Adding `Earnie.xcworkspace` discovers `Earnie-macOS` and `Earnie-iOS`.
2. Both schemes can be enabled simultaneously and remain enabled after relaunching XPlay.
3. `Earnie-macOS` can select `My Mac`; `Earnie-iOS` can select an installed iOS Simulator.
4. The status menu displays both enabled schemes and their selected destinations beneath
   `Earnie`.
5. Selecting either configuration in the status menu persists it, and one Play click
   builds and launches only that selected configuration.
6. Device placeholders and physical iOS devices are not selectable in the initial scope.
7. Removing or renaming a simulator does not silently redirect a launch to another device.
8. `Accept Macros` appears only in the global Settings section, defaults off, persists,
   and conditionally adds `-skipMacroValidation` to every build.
9. Existing `.xcodeproj` entries continue to load without data loss.
10. Empty, loading, incomplete, failure, and unavailable states are accessible through
    visible copy and VoiceOver labels.
