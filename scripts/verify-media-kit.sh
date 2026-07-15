#!/bin/sh
set -eu
root=
while [ "$#" -gt 0 ]; do case "$1" in --root) root=$2; shift 2;; *) echo "unknown argument: $1" >&2; exit 2;; esac; done
[ -n "$root" ] || { echo 'required: --root PATH' >&2; exit 2; }
if command -v python3 >/dev/null 2>&1; then py=python3; else py=python; fi
exec "$py" "$(dirname "$0")/verify-media-kit.py" "$root"
