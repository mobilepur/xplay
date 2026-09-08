# Release Notes

## Unreleased

## 1.1.6 — 2026-09-08

### Fixed

- Keep the XPlay menu open when selecting another project and update its visible
  project state in place.

## 1.1.5 — 2026-09-08

### Added

- Automatically remove build caches and logs unused for seven days.
- Keep build caches near 5 GB by removing the least recently used entries while
  protecting active builds, running apps, and the most recently used cache.

### Fixed

- Stop scheme discovery from remaining on Loading schemes indefinitely when
  Xcode package resolution stalls.

## 1.1.4 — 2026-09-07

### Changed

- Place a compact Open in Xcode icon at the right of the action row, beside Stop.
- Reduce the spacing between action buttons and give Run the remaining width.

### Fixed

- Keep Run, Stop, and Open at the same visible height in light and dark mode,
  including disabled states.

## 1.1.3 — 2026-09-07

### Fixed

- Keep the XPlay menu bar icon responsive and visible by using AppKit’s native
  status item image while idle.
- Match the visual width and corner radius of the Run and Open buttons while
  keeping Stop compact.

## 1.1.2 — 2026-09-07

### Added

- Add `run-dev.sh` as a short launcher for the local development build.
- Add a manual project refresh control to update branches and destinations on
  demand.

### Changed

- Keep cached branches and destinations when reopening the menu so it appears
  immediately without transient loading indicators.
- Show recent branch activity and worktree details with aligned, blue
  single-selection indicators.
- Tint Run and enabled settings switches blue, and use compact chevrons for
  device selection.

### Fixed

- Keep menu height stable while builds and destination refreshes are running.
- Preserve an open device picker during catalog and destination updates.
- Refresh branches and destinations when the selected project actually changes,
  including changes made in the project editor.

## 1.1.1 — 2026-09-06

### Changed

- Shorten the menu bar tooltip to XPlay while preserving build progress.

## 1.1.0 — 2026-09-06

### Added

- Show the three most recently active local branches and worktrees, with the
  remaining entries available through Show More in the section header.
- Open the selected project's working copy in Xcode with the new Open button
  beside Run. The current branch appears above both buttons.
- Reuse existing worktrees or create a separate worktree for a branch without
  one, preserving the original checkout and its uncommitted changes.
- Add Automatically Select Latest Branch in Settings, disabled by default.
  Run and Open refresh the selection when enabled; active builds keep their
  working copy.

### Changed

- Keep the menu open when clicking a branch, updating its checkmark and current
  branch label in place, including selections from Show More.
- Display branch names with small worktree subtitles and align their text and
  checkmarks with scheme rows.
- Persist the selected working copy per project and use it consistently for
  schemes, devices, builds, logs, and Xcode opening.

### Fixed

- Ignore stale scheme and destination responses after changing working copies.
- Show Git discovery failures and unavailable working copies without silently
  launching the original checkout.
- Keep multiple worktrees of the same branch separately selectable.

## 1.0.2 — 2026-09-05

### Fixed

- Align Quit with the other menu labels while keeping the whole row clickable and Command-Q available.
- Add a separate Change button for devices and keep the main menu visible while
  its device submenu is open.
- Restart the rebuilt macOS app on Play without closing other copies from different paths.
- Keep build data and logs separate for different containers and schemes, including worktrees.
- Refresh destinations at startup, when opening the status menu, and after switching projects;
  keep removed destinations visible as unavailable and show discovery failures with a retry hint.
- Exclude ineligible destinations and destinations with Xcode errors.
- Validate release versions against project metadata instead of a fixed version number.
- Prevent older releases from replacing a newer Homebrew Cask and serialize release updates.

## 1.0.1 — 2026-09-05

### Changed

- Enlarge the app icon's XPlay symbol and add a soft, diagonal background gradient.
- Simplify the README to a short introduction, installation, and updates.

### Fixed

- Use Homebrew's structured postflight steps for installation compatibility.

## 1.0.0 — 2026-09-05

### Added

- Build and launch selected macOS apps and iOS Simulator apps directly from the
  menu bar without keeping Xcode open.
- Add `.xcodeproj` and `.xcworkspace` containers, select projects in a sidebar,
  and configure enabled schemes and destinations through drilldowns.
- Choose the active project, scheme, Mac, iPhone, or iPad from the status menu.
- Configure the menu bar appearance and assign Play or Menu to left and right
  clicks while keeping one gesture available for each action.
- Stop an in-progress build or launch from the status menu or by clicking the
  configured Play gesture again.
- Show launch progress in the menu bar and Run Project button, retain separate
  build logs, and report launch failures.
- Optionally accept Swift macro validation after explicit confirmation.
- Use the XPlay symbol throughout the menu bar, Run Project button, README, and
  macOS application icon.
- Open matching GitHub release notes and the issue reporter from the About
  section.
