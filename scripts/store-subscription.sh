#!/bin/sh
# Host-side helper to store a provider subscription URL on the router without printing it.
set -u

router="${1:-${ROUTER:-}}"
if [ -z "$router" ]; then
  echo "usage: sh scripts/store-subscription.sh <ssh-user>@<router-ip>" >&2
  echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
  exit 2
fi

remote_path="${SUBSCRIPTION_REMOTE_PATH:-/jffs/home-edge-bootstrap/SUBSCRIPTION.local}"
known_hosts_file="${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}"
ssh_opts="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts_file}"

case "$remote_path" in
  /jffs/?*) ;;
  /jffs|/jffs/) echo "ERROR: SUBSCRIPTION_REMOTE_PATH must not be the JFFS root." >&2; exit 1 ;;
  *) echo "ERROR: SUBSCRIPTION_REMOTE_PATH must be under /jffs." >&2; exit 1 ;;
esac
case "$remote_path" in
  *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.|*/) echo "ERROR: SUBSCRIPTION_REMOTE_PATH must be a safe file path." >&2; exit 1 ;;
esac

mkdir -p "$(dirname "$known_hosts_file")"

if [ -n "${SUBSCRIPTION_URL:-}" ]; then
  url="$SUBSCRIPTION_URL"
else
  printf 'Paste provider subscription URL: ' >&2
  if [ -t 0 ]; then
    stty_orig=$(stty -g 2>/dev/null || true)
    stty -echo 2>/dev/null || true
    IFS= read -r url
    [ -n "$stty_orig" ] && stty "$stty_orig" 2>/dev/null || true
    printf '\n' >&2
  else
    IFS= read -r url
  fi
fi

single_line_url=$(printf '%s' "$url" | tr -d '\r\n')
[ "$url" = "$single_line_url" ] || {
  echo "ERROR: subscription URL must be a single line." >&2; exit 1
}

case "$url" in
  http://*|https://*) ;;
  *) echo "ERROR: subscription URL must start with http:// or https://." >&2; exit 1 ;;
esac

printf '%s\n' "$url" | ssh $ssh_opts -- "$router" "set -e; dir=\$(dirname '$remote_path'); mkdir -p \"\$dir\"; umask 077; cat > '$remote_path'; chmod 600 '$remote_path'; bytes=\$(wc -c < '$remote_path'); echo subscription_file='$remote_path'; echo subscription_bytes=\"\$bytes\""
