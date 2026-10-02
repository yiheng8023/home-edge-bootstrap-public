#!/bin/sh
# Resolve the site-built parser from a verified compressed runtime source.
set -eu
state=${HOME_EDGE_STATE_ROOT:-/jffs/home-edge-bootstrap-state}
bin=${SUBSCRIPTION_PARSER_BIN:-/tmp/home-edge-bootstrap-tools/yamlbridge}
archive="$state/runtime/yamlbridge.gz"
digest="$state/runtime/yamlbridge.sha256"
sha() { openssl dgst -sha256 "$1" | awk '{print $NF}'; }
[ -s "$archive" ] && [ -s "$digest" ] || { echo 'subscription-tools: parser runtime missing' >&2; exit 1; }
expected=$(cat "$digest")
case "$expected" in *[!a-f0-9]*|'') exit 1;; esac
[ ${#expected} -eq 64 ] || exit 1
if [ ! -x "$bin" ] || [ "$(sha "$bin")" != "$expected" ]; then
  [ ! -L "$(dirname "$bin")" ] && [ ! -L "$bin" ] || exit 1
  mkdir -p "$(dirname "$bin")"
  chmod 700 "$(dirname "$bin")"
  tmp="$bin.tmp.$$"
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  gzip -dc "$archive" >"$tmp"
  [ "$(sha "$tmp")" = "$expected" ] || exit 1
  chmod 700 "$tmp"
  mv "$tmp" "$bin"
fi
printf '%s\n' "$bin"
