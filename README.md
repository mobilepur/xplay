# XPlay

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/xplay-icon-dark.svg">
  <img src="XPlay/Assets.xcassets/XPlayIcon.imageset/XPlayIcon.svg" width="105" height="90" alt="XPlay icon">
</picture>

XPlay lets you build and run your Xcode projects from the macOS menu bar.
Keep coding in your favorite editor while XPlay handles the launch.

## Branches and worktrees

The menu shows the three most recently active local branches and working copies.
**Show More…** in the Recent Branches header lists the remaining entries. Activity combines Git commit/reflog
updates with modification times of uncommitted, non-ignored files; it is an
estimate rather than a history of every edit.

Click a branch to select its working copy while keeping the menu open. The
checkmark and branch label update so Run and Open remain directly available.
Existing worktrees are reused. Selecting
a branch without a worktree creates a separate one under
`~/Library/Application Support/XPlay/Worktrees`, leaving the original checkout
and its uncommitted changes in place. These worktrees remain available until you
remove them with Git.

The selected branch appears above **Run** and **Open**. Both use the selected
working copy: Run builds and launches it, and Open opens its Xcode project or
workspace in Xcode. Hover over a branch to see its folder and activity time.

Under Settings, **Automatically Select Latest Branch** follows the branch with
the most recent activity. It defaults to off. When enabled, XPlay refreshes the
selection on startup, when opening the menu or changing projects, and before
Run or Open. A running build keeps its working copy. Turn it off to select a
branch manually; the current selection is retained. If the newest branch cannot
provide this Xcode project, XPlay reports the error instead of launching an
older branch silently.

## Automatic build cache cleanup

After each Run finishes, fails, or is cancelled, XPlay cleans its disposable data
under `~/Library/Caches/XPlay` in the background. Build caches and logs unused for
seven days are removed. If build caches still exceed approximately 5 GB, the least
recently used caches are removed first.

Cleanup waits until all XPlay builds and launches have finished. Caches containing
running macOS apps are preserved, and the most recently used cache is kept when
enforcing the size target. These protections can temporarily leave more than 5 GB.
Older cache layouts are included. Removing caches makes the next affected build
slower and may require downloading dependencies again.

Project sources, saved settings, and Git worktrees are not part of this cleanup.

## Install

Requires macOS 15 or later, Xcode, and [Homebrew](https://brew.sh).

```sh
brew install --cask mobilepur/tap/xplay
```

## Update

```sh
brew upgrade --cask xplay
```
