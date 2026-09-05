#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/../.." && pwd)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/xplay-version-test.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT

# Exercise the real workflow checks with a subsequent release's metadata.
mkdir -p "$temporary_root/Tests/PackagingTests" "$temporary_root/.github"
cp -R "$repository_root/Scripts" "$temporary_root/Scripts"
cp -R "$repository_root/docs" "$temporary_root/docs"
cp -R "$repository_root/.github/workflows" "$temporary_root/.github/workflows"
cp "$repository_root/README.md" "$repository_root/project.yml" "$temporary_root/"
cp "$repository_root/Tests/PackagingTests/ReleaseWorkflowTests.sh" "$temporary_root/Tests/PackagingTests/"
ruby -ryaml -e '
  path = ARGV.fetch(0)
  spec = YAML.load_file(path)
  settings = spec.fetch("targets").fetch("XPlay").fetch("settings").fetch("base")
  settings["MARKETING_VERSION"] = "1.1.0"
  settings["CURRENT_PROJECT_VERSION"] = "3"
  File.write(path, YAML.dump(spec))
' "$temporary_root/project.yml"
printf '\n## 1.1.0 — Test release\n' >> "$temporary_root/docs/RELEASE_NOTES.md"
bash "$temporary_root/Tests/PackagingTests/ReleaseWorkflowTests.sh"
echo "Next-version workflow validation passed"

ruby "$repository_root/Scripts/verify-release-version.rb" "$temporary_root/project.yml" 1.1.0 3
for actual in '1.0.1 3' '1.1.0 2'; do
    read -r version build <<< "$actual"
    if ruby "$repository_root/Scripts/verify-release-version.rb" "$temporary_root/project.yml" "$version" "$build" >/dev/null 2>&1; then
        echo "Release validation accepted mismatched metadata: $actual" >&2
        exit 1
    fi
done

sed -i '' '/## 1.1.0/d' "$temporary_root/docs/RELEASE_NOTES.md"
if bash "$temporary_root/Tests/PackagingTests/ReleaseWorkflowTests.sh" >/dev/null 2>&1; then
    echo "Release validation accepted missing release notes" >&2
    exit 1
fi
echo "Mismatched package versions and missing release notes rejected"
