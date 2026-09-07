#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

exec "$repository_root/launch-dev"
