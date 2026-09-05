#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/../.." && pwd)"
ci_workflow="$repository_root/.github/workflows/ci.yml"
release_workflow="$repository_root/.github/workflows/release.yml"
build_script="$repository_root/Scripts/build-release.sh"
readme="$repository_root/README.md"
release_guide="$repository_root/docs/RELEASING.md"
release_notes="$repository_root/docs/RELEASE_NOTES.md"
project_spec="$repository_root/project.yml"

grep -Fq 'runs-on: macos-15' "$ci_workflow"
grep -Fq 'xcodebuild test' "$ci_workflow"
grep -Fq 'Tests/PackagingTests/ReleasePackageTests.sh' "$ci_workflow"
grep -Fq 'Tests/PackagingTests/ReleaseWorkflowTests.sh' "$ci_workflow"

grep -Fq 'runs-on: macos-15' "$release_workflow"
grep -Fq 'git merge-base --is-ancestor "$GITHUB_SHA" origin/main' "$release_workflow"
grep -Fq 'persist-credentials: false' "$release_workflow"
grep -Fq 'Scripts/render-homebrew-cask.sh' "$release_workflow"
grep -Fq 'checksums.txt' "$release_workflow"
grep -Fq 'gh release download' "$release_workflow"
grep -Fq 'shasum -a 256 -c checksums.txt' "$release_workflow"
grep -Fq 'mobilepur/homebrew-tap' "$release_workflow"
grep -Fq 'HOMEBREW_TAP_GITHUB_TOKEN' "$release_workflow"
if grep -Fq -- '--clobber' "$release_workflow"; then
    echo "Release workflow mutates assets already published for a tag" >&2
    exit 1
fi

publish_line="$(grep -nF 'name: Publish release package' "$release_workflow" | cut -d: -f1)"
tap_checkout_line="$(grep -nF 'repository: mobilepur/homebrew-tap' "$release_workflow" | cut -d: -f1)"
if [[ "$tap_checkout_line" -le "$publish_line" ]]; then
    echo "Homebrew tap credentials are exposed before the release build finishes" >&2
    exit 1
fi

if grep -Eq 'APPLE_|BUILD_CERTIFICATE|P12_PASSWORD|DEVELOPER_ID' "$release_workflow" "$build_script"; then
    echo "Release automation unexpectedly requires Apple signing credentials" >&2
    exit 1
fi

grep -Fq 'MARKETING_VERSION: "1.0.1"' "$project_spec"
grep -Fq 'CURRENT_PROJECT_VERSION: "2"' "$project_spec"
grep -Fq '## 1.0.1' "$release_notes"
grep -Fq 'brew install --cask mobilepur/tap/xplay' "$readme"
grep -Fq '`HOMEBREW_TAP_GITHUB_TOKEN`' "$release_guide"
grep -Fq 'docs/RELEASE_NOTES.md' "$release_guide"
grep -Fq 'ad-hoc' "$release_guide"

test ! -e "$repository_root/Casks/xplay.rb"
test ! -e "$repository_root/Formula/xplay.rb"
