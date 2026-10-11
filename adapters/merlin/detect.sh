#!/bin/sh
# Read-only candidate probe; not official-firmware or model-support attestation.
set -eu
[ -d /jffs ] || exit 1
command -v nvram >/dev/null 2>&1 || exit 1
product=$(nvram get productid) || exit 1
[ -n "$product" ] || exit 1
exit 0
