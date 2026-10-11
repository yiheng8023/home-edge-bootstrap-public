#!/bin/sh
# Device-neutral dispatch. Detection and target conventions belong to adapters.
set -eu

root=$(CDPATH= cd "$(dirname "$0")" && pwd)
adapter="${BOOTSTRAP_ADAPTER:-auto}"

if [ "$adapter" = "auto" ]; then
  matches=''; count=0
  for directory in "$root"/adapters/*; do
    [ -d "$directory" ] && [ ! -L "$directory" ] || continue
    id=${directory##*/}
    case "$id" in ''|*[!A-Za-z0-9_-]*) continue ;; esac
    [ -f "$directory/detect.sh" ] && [ ! -L "$directory/detect.sh" ] || continue
    if sh "$directory/detect.sh"; then matches="$matches $id"; count=$((count + 1)); fi
  done
  if [ "$count" -ne 1 ]; then
    printf 'adapter_state=needs_selection\nadapter_candidates=%s\n' "$matches" >&2
    echo 'Automatic detection did not find exactly one candidate. Use guided diagnosis and explicitly choose an installed device adapter.' >&2
    quoted_entry=$(printf '%s' "$root/bootstrap.sh" | sed "s/'/'\\\\''/g")
    printf "Inspect installed adapters below this project, then use: BOOTSTRAP_ADAPTER=<adapter-id> sh '%s' --dry-run\n" "$quoted_entry" >&2
    printf "Example for the current reference adapter, after confirming an ASUSWRT-Merlin target: BOOTSTRAP_ADAPTER=merlin sh '%s' --dry-run\n" "$quoted_entry" >&2
    exit 2
  fi
  adapter=${matches# }
fi
case "$adapter" in
  ''|*[!A-Za-z0-9_-]*) echo 'Invalid adapter identifier; no adapter was executed.' >&2; exit 2 ;;
esac
entry="$root/adapters/$adapter/bootstrap.sh"
[ -d "$root/adapters/$adapter" ] && [ ! -L "$root/adapters/$adapter" ] && [ -f "$entry" ] && [ ! -L "$entry" ] || { echo "adapter_state=unavailable: $adapter" >&2; exit 2; }
printf 'adapter_candidate=%s\n' "$adapter"
# Candidate detection is not firmware acceptance. The adapter owns plan/apply gates.
exec sh "$entry" "$@"
