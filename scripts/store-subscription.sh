#!/bin/sh
# Host-side helper to store a provider subscription URL on the router without printing it.
set -u

router="${1:-${ROUTER:-}}"
if [ -z "$router" ]; then
  echo "usage: sh scripts/store-subscription.sh <ssh-user>@<router-ip>" >&2
  echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
  exit 2
fi

remote_path="${SUBSCRIPTION_REMOTE_PATH:-/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local}"
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

stty_orig=""
restore_input_echo() {
  if [ -n "$stty_orig" ]; then
    stty "$stty_orig" 2>/dev/null || true
    stty_orig=""
  fi
}
handle_input_signal() {
  signal_status=$1
  restore_input_echo
  exit "$signal_status"
}
trap restore_input_echo EXIT
trap 'handle_input_signal 129' HUP
trap 'handle_input_signal 130' INT
trap 'handle_input_signal 143' TERM

if [ -n "${SUBSCRIPTION_URL:-}" ]; then
  url="$SUBSCRIPTION_URL"
else
  printf 'Paste provider subscription URL: ' >&2
  if [ "${HOME_EDGE_STDIN_IS_TTY:-0}" = 1 ] || [ -t 0 ]; then
    stty_orig=$(stty -g 2>/dev/null || true)
    if [ -n "$stty_orig" ]; then
      stty -echo 2>/dev/null || stty_orig=""
    fi
    IFS= read -r url
    restore_input_echo
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

remote_script='
set -eu
remote_path="__REMOTE_PATH__"
dir=$(dirname "$remote_path")
tmp_path="${remote_path}.tmp.$$"
cleanup() {
  rm -f "$tmp_path" 2>/dev/null || true
}
handle_signal() {
  cleanup
  trap - EXIT
  exit 130
}
trap cleanup EXIT
trap handle_signal HUP INT TERM
mkdir -p "$dir"
umask 077
[ ! -L "$remote_path" ] || {
  echo "store-subscription: refusing symbolic-link target" >&2
  exit 1
}
cat >"$tmp_path"
[ -s "$tmp_path" ] || {
  echo "store-subscription: payload is empty" >&2
  exit 1
}
chmod 600 "$tmp_path"
mv -f "$tmp_path" "$remote_path"
trap - EXIT HUP INT TERM
bytes=$(wc -c <"$remote_path")
echo "subscription_file=$remote_path"
echo "subscription_bytes=$bytes"
'
remote_script=$(printf '%s' "$remote_script" | sed "s#__REMOTE_PATH__#$remote_path#g")
printf '%s\n' "$url" | ssh $ssh_opts -- "$router" "$remote_script"
