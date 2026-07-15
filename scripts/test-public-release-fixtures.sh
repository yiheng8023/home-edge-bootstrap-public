#!/bin/sh
set -eu
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
python_cmd=
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)'; then
    python_cmd=$candidate
    break
  fi
done
[ -n "$python_cmd" ] || { echo 'Python 3 is required' >&2; exit 1; }
exec "$python_cmd" "$repo/scripts/test-public-release-fixtures.py" --mode posix --source "$repo"
