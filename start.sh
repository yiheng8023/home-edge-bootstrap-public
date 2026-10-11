#!/bin/sh
# Resolve the extracted package beside this file, regardless of the caller's cwd.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ ! -f "$repo/scripts/launch-tui.sh" ]; then
  echo 'Extract the whole package before opening start.sh.' >&2
  exit 2
fi
exec sh "$repo/scripts/launch-tui.sh" --repo "$repo" "$@"
