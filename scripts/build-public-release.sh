#!/bin/sh
set -eu
repo=
version=
prepared=
output=
commit=HEAD
fixture_mode=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo=$2; shift 2 ;;
    --version) version=$2; shift 2 ;;
    --prepared-dir) prepared=$2; shift 2 ;;
    --output) output=$2; shift 2 ;;
    --commit) commit=$2; shift 2 ;;
    --fixture-mode) fixture_mode=--fixture-mode; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] && [ -n "$version" ] && [ -n "$prepared" ] && [ -n "$output" ] || {
  echo 'required: --repo --version --prepared-dir --output' >&2
  exit 2
}
python_cmd=
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)'; then
    python_cmd=$candidate
    break
  fi
done
[ -n "$python_cmd" ] || { echo 'Python 3 is required' >&2; exit 1; }
exec "$python_cmd" "$(dirname "$0")/public-release.py" build --repo "$repo" --version "$version" --prepared-dir "$prepared" --output "$output" --commit "$commit" $fixture_mode
