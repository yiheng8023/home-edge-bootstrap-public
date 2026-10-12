#!/bin/sh
# Read-only candidate probe; not official-firmware or model-support attestation.
set -eu
[ -d /jffs ] || exit 1
nvram_command=$(command -v nvram 2>/dev/null || which nvram 2>/dev/null || true)
[ -n "$nvram_command" ] && [ -x "$nvram_command" ] || exit 1
product=$("$nvram_command" get productid) || exit 1
[ -n "$product" ] || exit 1
exit 0
