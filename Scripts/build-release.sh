#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
output_directory="${1:-$repository_root/dist}"
archive="$output_directory/XPlay.tar.gz"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/xplay-release.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
derived_data_path="$temporary_directory/DerivedData"
staging_directory="$temporary_directory/package"

if [[ -e "$archive" ]]; then
    echo "Release archive already exists: $archive" >&2
    exit 1
fi

xcodebuild build -quiet \
    -project "$repository_root/XPlay.xcodeproj" \
    -scheme XPlay \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data_path" \
    CODE_SIGNING_ALLOWED=NO

built_app="$derived_data_path/Build/Products/Release/XPlay.app"
app="$staging_directory/XPlay.app"
mkdir -p "$staging_directory" "$output_directory"
ditto "$built_app" "$app"

codesign --force --deep --options runtime --sign - "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/XPlay" -verify_arch arm64 x86_64

tar -czf "$archive" -C "$staging_directory" XPlay.app

echo "$archive"
