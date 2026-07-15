#!/bin/sh
# Host-side guarded live self-heal enable helper for macOS/Linux/Git Bash.
set -u

router="${1:-${ROUTER:-}}"
if [ -z "$router" ]; then
  echo "usage: sh scripts/enable-live-self-heal.sh <ssh-user>@<router-ip>" >&2
  echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
  exit 2
fi

log_path="${LOG_PATH:-/tmp/home-edge-enable-live-self-heal.log}"
known_hosts_file="${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}"
ssh_timeout="${SSH_CONNECT_TIMEOUT_SEC:-8}"
ssh_opts="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=$ssh_timeout -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts_file}"

mkdir -p "$(dirname "$log_path")" "$(dirname "$known_hosts_file")"

router_script=$(CDPATH= cd "$(dirname "$0")" && pwd)/enable-live-self-heal-router.sh
[ -r "$router_script" ] || {
  echo "ERROR: missing $router_script" >&2
  exit 1
}
payload=$(base64 <"$router_script" | tr -d '\r\n') || {
  echo "ERROR: cannot encode $router_script" >&2
  exit 1
}

printf '%s\n' "Enable live self-heal log: $log_path"
# shellcheck disable=SC2086
if printf '%s' "$payload" | ssh $ssh_opts -- "$router" 'base64 -d | sh -s' >"$log_path" 2>&1; then
  cat "$log_path"
  exit 0
fi
status=$?
cat "$log_path" 2>/dev/null || true
exit "$status"
