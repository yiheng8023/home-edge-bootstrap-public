#!/bin/sh
set -eu
umask 077
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
ui=${HOME_EDGE_DASHBOARD_DIR:-/jffs/ShellCrash/ui}
source=${HOME_EDGE_DASHBOARD_DEFAULTS_SOURCE:-$script_dir/home-edge-dashboard-defaults.js}
[ -f "$source" ] || source="$script_dir/dashboard-defaults.js"
[ -f "$ui/index.html" ] || { echo dashboard_defaults=dashboard_absent; exit 0; }
[ ! -L "$ui" ] && [ ! -L "$ui/index.html" ] || exit 1
if [ "${1:-}" = --remove ]; then
  tmp="$ui/.home-edge-defaults.$$"
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  if grep -Fq '<!-- home-edge-dashboard-defaults -->' "$ui/index.html"; then
    [ ! -L "$ui/home-edge-defaults.js" ] && cmp -s "$ui/home-edge-defaults.js" "$source" || exit 1
    sed 's#<!-- home-edge-dashboard-defaults --><script src="./home-edge-defaults.js?v=1"></script>##' "$ui/index.html" >"$tmp"
    chmod 644 "$tmp"; mv "$tmp" "$ui/index.html"
    rm -f "$ui/home-edge-defaults.js"
  fi
  echo dashboard_defaults=removed
  exit 0
fi
# Limit injection to the storage contract inspected in supported Yacd-meta builds.
grep -l 'yacd.metacubex.one' "$ui"/assets/index-*.js >/dev/null 2>&1 || { echo dashboard_defaults=unsupported; exit 0; }
[ -f "$source" ] || exit 1
tmp="$ui/.home-edge-defaults.$$"
trap 'rm -f "$tmp"' EXIT HUP INT TERM
cp "$source" "$ui/home-edge-defaults.js"
chmod 644 "$ui/home-edge-defaults.js"
if ! grep -Fq '<!-- home-edge-dashboard-defaults -->' "$ui/index.html"; then
  grep -q '</head>' "$ui/index.html" || exit 1
  sed 's#</head>#<!-- home-edge-dashboard-defaults --><script src="./home-edge-defaults.js?v=1"></script></head>#' "$ui/index.html" >"$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$ui/index.html"
fi
echo dashboard_defaults=ready
