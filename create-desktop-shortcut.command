#!/bin/sh
set -eu
repo=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
exec sh "$repo/create-desktop-shortcut.sh" "$@"
