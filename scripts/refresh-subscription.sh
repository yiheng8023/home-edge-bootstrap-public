#!/bin/sh
# Host-side helper to refresh the router subscription cache. DRY-RUN by default.
set -u

router="${1:-${ROUTER:-}}"
if [ -z "$router" ]; then
  echo "usage: sh scripts/refresh-subscription.sh <ssh-user>@<router-ip>" >&2
  echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
  exit 2
fi

known_hosts_file="${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}"
ssh_opts="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts_file}"
apply="${APPLY:-0}"

mkdir -p "$(dirname "$known_hosts_file")"

reject_single_quote() {
  name="$1"
  value="$2"
  case "$value" in
    *\'*) echo "ERROR: $name must not contain a single quote." >&2; exit 1 ;;
  esac
  single_line_value=$(printf '%s' "$value" | tr -d '\r\n')
  [ "$value" = "$single_line_value" ] || {
    echo "ERROR: $name must be a single line." >&2; exit 1
  }
}

mode="SUBSCRIPTION_DRY_RUN=1"
[ "$apply" = "1" ] && mode="SUBSCRIPTION_DRY_RUN=0"
if [ -n "${SUBSCRIPTION_CONVERTER_BASE_URL:-}" ]; then
  reject_single_quote SUBSCRIPTION_CONVERTER_BASE_URL "$SUBSCRIPTION_CONVERTER_BASE_URL"
  mode="$mode SUBSCRIPTION_CONVERTER_BASE_URL='$SUBSCRIPTION_CONVERTER_BASE_URL'"
fi
if [ -n "${SUBSCRIPTION_FETCH_PROXY:-}" ]; then
  reject_single_quote SUBSCRIPTION_FETCH_PROXY "$SUBSCRIPTION_FETCH_PROXY"
  mode="$mode SUBSCRIPTION_FETCH_PROXY='$SUBSCRIPTION_FETCH_PROXY'"
fi
if [ -n "${SUBSCRIPTION_CONVERTER_TARGET:-}" ]; then
  reject_single_quote SUBSCRIPTION_CONVERTER_TARGET "$SUBSCRIPTION_CONVERTER_TARGET"
  mode="$mode SUBSCRIPTION_CONVERTER_TARGET='$SUBSCRIPTION_CONVERTER_TARGET'"
fi
if [ -n "${SUBSCRIPTION_CONVERTER_CONFIG_URL:-}" ]; then
  reject_single_quote SUBSCRIPTION_CONVERTER_CONFIG_URL "$SUBSCRIPTION_CONVERTER_CONFIG_URL"
  mode="$mode SUBSCRIPTION_CONVERTER_CONFIG_URL='$SUBSCRIPTION_CONVERTER_CONFIG_URL'"
fi
if [ -n "${SUBSCRIPTION_APPLY_PATH:-}" ]; then
  reject_single_quote SUBSCRIPTION_APPLY_PATH "$SUBSCRIPTION_APPLY_PATH"
  mode="$mode SUBSCRIPTION_APPLY_PATH='$SUBSCRIPTION_APPLY_PATH'"
fi
if [ -n "${SUBSCRIPTION_RELOAD_CMD:-}" ]; then
  reject_single_quote SUBSCRIPTION_RELOAD_CMD "$SUBSCRIPTION_RELOAD_CMD"
  mode="$mode SUBSCRIPTION_RELOAD_CMD='$SUBSCRIPTION_RELOAD_CMD'"
fi
[ "${SUBSCRIPTION_ALLOW_REMOTE_CONVERTER:-0}" = "1" ] && mode="$mode SUBSCRIPTION_ALLOW_REMOTE_CONVERTER=1"

{
  echo "set -e"
  printf '%s sh /jffs/scripts/home-edge-update-sub.sh\n' "$mode"
  echo "tail -n 8 /tmp/update-sub.log 2>/dev/null || true"
} | ssh $ssh_opts -- "$router" 'tr -d "\r" | sh -s'
