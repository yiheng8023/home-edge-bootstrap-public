#!/bin/sh
set -eu
root=
while [ "$#" -gt 0 ]; do case "$1" in --root) root=$2; shift 2;; *) echo "unknown argument: $1" >&2; exit 2;; esac; done
[ -n "$root" ] || { echo 'required: --root PATH' >&2; exit 2; }
py=
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then py=$candidate; break; fi
done
[ -n "$py" ] || { echo 'Python 3 is required' >&2; exit 1; }
exec "$py" "$(dirname "$0")/verify-media-kit.py" "$root"
