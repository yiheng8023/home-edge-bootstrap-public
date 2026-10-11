#!/bin/sh
set -eu
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-adapter-dispatch.XXXXXX")
trap 'rm -rf "$tmp"' 0 HUP INT TERM
fail() { echo "adapter_dispatch_fixture_tests=failed: $*" >&2; exit 1; }
cp "$repo/bootstrap.sh" "$tmp/bootstrap.sh"
mkdir -p "$tmp/adapters/reference-a"
printf '#!/bin/sh\nexit 0\n' >"$tmp/adapters/reference-a/detect.sh"
printf '#!/bin/sh\nprintf "fixture_adapter=a argument=%%s\\n" "$1"\n' >"$tmp/adapters/reference-a/bootstrap.sh"
sh "$tmp/bootstrap.sh" --dry-run >"$tmp/auto"
grep -Fq 'fixture_adapter=a argument=--dry-run' "$tmp/auto" || fail 'neutral dispatch does not preserve argument'
mkdir -p "$tmp/adapters/reference-b"
cp "$tmp/adapters/reference-a/detect.sh" "$tmp/adapters/reference-b/detect.sh"
printf '#!/bin/sh\necho fixture_adapter=b\n' >"$tmp/adapters/reference-b/bootstrap.sh"
if sh "$tmp/bootstrap.sh" --dry-run >"$tmp/ambiguous" 2>&1; then fail 'ambiguous adapters were auto-selected'; fi
grep -Fq 'adapter_state=needs_selection' "$tmp/ambiguous" || fail 'ambiguous detector did not request selection'
grep -Fq "BOOTSTRAP_ADAPTER=<adapter-id> sh '$tmp/bootstrap.sh' --dry-run" "$tmp/ambiguous" || fail 'selection failure has no project-bound executable override guidance'
if grep -Fq 'fixture_adapter=' "$tmp/ambiguous"; then fail 'ambiguous selection executed an adapter'; fi
BOOTSTRAP_ADAPTER=reference-b sh "$tmp/bootstrap.sh" --dry-run >"$tmp/explicit"
grep -Fq 'fixture_adapter=b' "$tmp/explicit" || fail 'explicit adapter selection failed'
if BOOTSTRAP_ADAPTER=../reference-a sh "$tmp/bootstrap.sh" >"$tmp/traversal" 2>&1; then fail 'unsafe adapter identifier accepted'; fi
if BOOTSTRAP_ADAPTER=missing sh "$tmp/bootstrap.sh" >"$tmp/missing" 2>&1; then fail 'missing adapter accepted'; fi
printf '#!/bin/sh\nexit 1\n' >"$tmp/adapters/reference-a/detect.sh"
printf '#!/bin/sh\nexit 1\n' >"$tmp/adapters/reference-b/detect.sh"
if sh "$tmp/bootstrap.sh" >"$tmp/no-match" 2>&1; then fail 'no candidate was treated as support'; fi
echo adapter_dispatch_fixture_tests=ready
