#!/bin/sh
# Local no-wall readiness check. Does not contact the network.
set -u

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
bundle_dir="$repo/bundle"
missing_tools=""
for tool in ssh tar gzip base64; do
  command -v "$tool" >/dev/null 2>&1 || missing_tools="$missing_tools $tool"
done

echo "# No-Wall Readiness"
echo
echo "## Local Tools"
if [ -n "$missing_tools" ]; then
  echo "status=missing_tools"
  echo "missing_tools=$missing_tools"
else
  echo "status=tools_ready"
fi
echo
echo "## Offline Bundle"
bundle_ready=1
for f in mihomo-linux-arm64 ShellCrash.tar.gz SHA256SUMS MANIFEST.json; do
  if [ -s "$bundle_dir/$f" ]; then
    echo "bundle/$f=present"
  else
    echo "bundle/$f=missing"
    bundle_ready=0
  fi
done

if [ "$bundle_ready" = "1" ]; then
  tmp_log=$(mktemp "${TMPDIR:-/tmp}/home-edge-no-wall-verify.XXXXXX") || exit 1
  trap 'rm -f "$tmp_log"' EXIT HUP INT TERM
  if sh "$repo/scripts/verify-bundle.sh" "$bundle_dir" >"$tmp_log" 2>&1; then
    rm -f "$tmp_log"
    trap - EXIT HUP INT TERM
    echo "bundle_state=verified"
  else
    echo "bundle_state=invalid"
    cat "$tmp_log"
    rm -f "$tmp_log"
    trap - EXIT HUP INT TERM
    exit 1
  fi
else
  echo "bundle_state=missing"
fi
echo
echo "## Interpretation"
if [ -n "$missing_tools" ]; then
  echo "Install or repair missing local tools before operating without proxy."
  exit 1
elif [ "$bundle_ready" = "1" ]; then
  echo "This checkout can perform a no-wall runtime restore when the target router is supported."
else
  echo "This checkout can configure an existing ShellCrash/Mihomo runtime, but cannot perform a fresh no-wall runtime install until the bundle is supplied from a trusted reachable source."
fi
