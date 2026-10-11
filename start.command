#!/bin/sh
# macOS Terminal entry; keep the same guide and confirmation gates.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$repo/start.sh" "$@"
