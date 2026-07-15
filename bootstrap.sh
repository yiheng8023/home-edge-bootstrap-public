#!/bin/sh
# Portable entrypoint. It chooses a target adapter and delegates.
set -u

root=$(CDPATH= cd "$(dirname "$0")" && pwd)
adapter="${BOOTSTRAP_ADAPTER:-auto}"

if [ "$adapter" = "auto" ]; then
  if [ -d /jffs ]; then
    adapter="merlin"
  else
    echo "ERROR: cannot auto-detect adapter; set BOOTSTRAP_ADAPTER=merlin" >&2
    exit 1
  fi
fi

case "$adapter" in
  merlin)
    exec sh "$root/adapters/merlin/bootstrap.sh" "$@"
    ;;
  *)
    echo "ERROR: unsupported adapter '$adapter'" >&2
    exit 1
    ;;
esac
