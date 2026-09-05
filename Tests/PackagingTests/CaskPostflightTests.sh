#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/../.." && pwd)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/xplay-cask-postflight.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT

generated_cask="$temporary_root/xplay.rb"
checksum="$(printf '%064d' 0)"

bash "$repository_root/Scripts/render-homebrew-cask.sh" 1.0.0 "$checksum" > "$generated_cask"
ruby "$repository_root/Tests/PackagingTests/CaskPostflightTests.rb" "$generated_cask" "$temporary_root"
