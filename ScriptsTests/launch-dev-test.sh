#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/xplay-launch-dev-test.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

mkdir "$temporary_directory/bin"
command_log="$temporary_directory/commands.log"

cat > "$temporary_directory/bin/fake-command" <<'EOF'
#!/bin/sh

command_name=$(basename "$0")
printf '%s|%s' "$command_name" "$PWD" >> "$XPLAY_COMMAND_LOG"
for argument in "$@"; do
    printf '|%s' "$argument" >> "$XPLAY_COMMAND_LOG"
done
printf '\n' >> "$XPLAY_COMMAND_LOG"

if [ "$command_name" = "xcodebuild" ]; then
    exit "${XPLAY_XCODEBUILD_EXIT:-0}"
fi

if [ "$command_name" = "pkill" ]; then
    exit 1
fi
EOF

chmod +x "$temporary_directory/bin/fake-command"
ln -s fake-command "$temporary_directory/bin/xcodebuild"
ln -s fake-command "$temporary_directory/bin/pkill"
ln -s fake-command "$temporary_directory/bin/open"

derived_data_path="$temporary_directory/Derived Data"

(
    cd "$temporary_directory"
    PATH="$temporary_directory/bin:/usr/bin:/bin" \
        XPLAY_COMMAND_LOG="$command_log" \
        XPLAY_DERIVED_DATA_PATH="$derived_data_path" \
        "$repository_root/launch-dev"
)

expected_log="$temporary_directory/expected.log"
printf '%s\n' \
    "xcodebuild|$repository_root|build|-project|XPlay.xcodeproj|-scheme|XPlay|-configuration|Debug|-destination|platform=macOS|-derivedDataPath|$derived_data_path" \
    "pkill|$repository_root|-x|XPlay" \
    "open|$repository_root|-n|$derived_data_path/Build/Products/Debug/XPlay.app" \
    > "$expected_log"

diff -u "$expected_log" "$command_log"

: > "$command_log"
if (
    cd "$temporary_directory"
    PATH="$temporary_directory/bin:/usr/bin:/bin" \
        XPLAY_COMMAND_LOG="$command_log" \
        XPLAY_XCODEBUILD_EXIT=17 \
        XPLAY_DERIVED_DATA_PATH="$derived_data_path" \
        "$repository_root/launch-dev"
); then
    echo "launch-dev unexpectedly continued after a failed build" >&2
    exit 1
fi

test "$(wc -l < "$command_log" | tr -d ' ')" = "1"
grep -q '^xcodebuild|' "$command_log"
