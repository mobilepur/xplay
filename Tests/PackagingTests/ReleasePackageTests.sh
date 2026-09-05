#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/../.." && pwd)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/xplay-package-test.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT

output_directory="$temporary_root/output"
archive="$output_directory/XPlay.tar.gz"
extracted_directory="$temporary_root/extracted"

bash "$repository_root/Scripts/build-release.sh" "$output_directory"

test -f "$archive"
mkdir -p "$extracted_directory"
tar -xzf "$archive" -C "$extracted_directory"

app="$extracted_directory/XPlay.app"
test -x "$app/Contents/MacOS/XPlay"
test -f "$app/Contents/Resources/AppIcon.icns"
plutil -lint "$app/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = "de.mobilepur.XPlay"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
test "$app_version" = "1.0.0"
test "$build_number" = "1"

codesign --verify --deep --strict "$app"
app_signature="$(codesign --display --verbose=4 "$app" 2>&1)"
[[ "$app_signature" = *"runtime"* ]]
lipo "$app/Contents/MacOS/XPlay" -verify_arch arm64 x86_64
test -z "$(find "$app" -iname '*XCTest*' -print -quit)"

checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"
generated_cask="$temporary_root/xplay.rb"
bash "$repository_root/Scripts/render-homebrew-cask.sh" "$app_version" "$checksum" > "$generated_cask"

ruby -c "$generated_cask"
brew style "$generated_cask"
grep -Fq "version \"$app_version\"" "$generated_cask"
grep -Fq "sha256 \"$checksum\"" "$generated_cask"
grep -Fq 'url "https://github.com/mobilepur/xplay/releases/download/v#{version}/XPlay.tar.gz"' "$generated_cask"
grep -Fq 'app "XPlay.app"' "$generated_cask"
grep -Fq 'quit: "de.mobilepur.XPlay"' "$generated_cask"
grep -Fq '"~/Library/Caches/XPlay"' "$generated_cask"
grep -Fq 'system_command "/usr/bin/xattr"' "$generated_cask"
! grep -Fq 'version :latest' "$generated_cask"
! grep -Fq 'sha256 :no_check' "$generated_cask"

if bash "$repository_root/Scripts/render-homebrew-cask.sh" "v$app_version" "$checksum" >/dev/null 2>&1; then
    echo "Cask renderer accepted an invalid version" >&2
    exit 1
fi
if bash "$repository_root/Scripts/render-homebrew-cask.sh" "$app_version" invalid >/dev/null 2>&1; then
    echo "Cask renderer accepted an invalid checksum" >&2
    exit 1
fi

bash "$repository_root/Tests/PackagingTests/CaskPostflightTests.sh"
