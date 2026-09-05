# Releasing

Pushing a version tag runs `.github/workflows/release.yml`. The workflow tests
the project, builds and ad-hoc signs a universal Apple Silicon and Intel app,
publishes the archive and its checksum to GitHub, and updates the versioned Cask
in `mobilepur/homebrew-tap`.

The tag must match `MARKETING_VERSION` in `project.yml` and point to a commit
already reachable from `main`.

## Required GitHub Actions secret

- `HOMEBREW_TAP_GITHUB_TOKEN`: Fine-grained personal access token restricted to
  the `mobilepur/homebrew-tap` repository with only **Contents: Read and write**.

Use an expiration date and rotate the token when it expires. Do not reuse a
broad personal or GitHub CLI token. GitHub supplies the separate `GITHUB_TOKEN`
used to publish the release in this repository.

## Distribution security

The generated Cask pins a version-specific GitHub Release URL and the archive's
SHA-256. Like GitHub Account Switcher and xlocal, the app is not Developer
ID-signed or notarized; the Cask removes the quarantine attribute after Homebrew
verifies the pinned archive checksum.

## Release steps

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`,
   then run `xcodegen generate`.
2. Move the relevant entries in `docs/RELEASE_NOTES.md` from **Unreleased** to
   the new version.
3. Run the full Xcode test suite and
   `bash Tests/PackagingTests/ReleaseWorkflowTests.sh`,
   `bash Tests/PackagingTests/ReleaseVersionTests.sh`,
   `ruby Tests/PackagingTests/HomebrewUpdateTests.rb`, and
   `bash Tests/PackagingTests/ReleasePackageTests.sh`. Package version and build
   metadata must match `project.yml`.
4. Merge the release commit into `main`.
5. Create and push a matching tag such as `v1.0.0` from that `main` commit.
6. Verify that the GitHub release contains `XPlay.tar.gz` and `checksums.txt`.
7. Verify that `mobilepur/homebrew-tap` contains a Cask with the same version
   and archive checksum.
8. Run `brew upgrade --cask xplay` or perform a fresh Cask installation.

Release assets are immutable after publication. Re-running the workflow for the
same tag downloads and verifies the existing archive and checksum, then repairs
only the Homebrew Cask when that version is still current. An older release
never replaces a newer Cask. All release tags share one workflow concurrency
group with `queue: max`, so pending releases wait instead of replacing each other
(up to [GitHub's limit of 100 pending runs](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)).
The tap updater fetches the latest tap state before comparing numeric versions.
Changed artifacts require a new version and tag.

These safeguards apply to tags containing this workflow. Re-running a historical
workflow from before the safeguards were added still executes its old update
logic; do not use those runs to repair the current Cask.
