#!/bin/bash

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 TAP_DIRECTORY GENERATED_CASK" >&2
    exit 64
fi

tap_directory="$1"
generated_cask="$2"

# Read the latest tap state after the workflow's shared release lock is acquired.
git -C "$tap_directory" fetch origin main
git -C "$tap_directory" merge --ff-only origin/main

if ruby - "$tap_directory/Casks/xplay.rb" "$generated_cask" <<'RUBY'
require "rubygems/version"

def version(path)
  value = File.read(path)[/^  version "([0-9]+\.[0-9]+\.[0-9]+)"$/, 1]
  abort "Cannot read a release version from #{path}" unless value

  Gem::Version.new(value)
end

candidate = version(ARGV.fetch(1))
if File.exist?(ARGV.fetch(0)) && version(ARGV.fetch(0)) > candidate
  puts "Skipping older Homebrew release #{candidate}"
  exit 2
end
RUBY
then
    :
else
    result="$?"
    # A downgrade is an intentional no-op; malformed metadata must fail closed.
    if [[ "$result" -eq 2 ]]; then
        exit 0
    fi
    exit "$result"
fi

install -m 644 "$generated_cask" "$tap_directory/Casks/xplay.rb"
git -C "$tap_directory" config user.name "github-actions[bot]"
git -C "$tap_directory" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$tap_directory" add Casks/xplay.rb
if git -C "$tap_directory" diff --cached --quiet; then
    exit 0
fi
git -C "$tap_directory" commit -m "Brew cask update for xplay version ${GITHUB_REF_NAME}"
git -C "$tap_directory" push origin HEAD:main
