#!/bin/sh
# Host-side repair for the project-owned Merlin boot hook and self-heal cron.
set -u

router="${1:-${ROUTER:-}}"
if [ -z "$router" ]; then
  echo "usage: sh scripts/repair-self-heal-registration.sh <ssh-user>@<router-ip>" >&2
  echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
  exit 2
fi

log_path="${LOG_PATH:-/tmp/home-edge-repair-self-heal-registration.log}"
known_hosts_file="${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}"
ssh_timeout="${SSH_CONNECT_TIMEOUT_SEC:-8}"
ssh_opts="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=$ssh_timeout -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts_file}"
mkdir -p "$(dirname "$log_path")" "$(dirname "$known_hosts_file")"

remote_script='set -eu
reconciler=/jffs/scripts/home-edge-reconcile-self-heal.sh
[ -x "$reconciler" ] || { echo "repair-self-heal-registration: ERROR: lifecycle reconciler is not deployed" >&2; exit 1; }
sh "$reconciler" --install'

printf '%s\n' "Lifecycle registration repair log: $log_path"
# shellcheck disable=SC2086
printf '%s' "$remote_script" | ssh $ssh_opts -- "$router" 'tr -d "\r" | sh -s' >"$log_path" 2>&1
status=$?
if [ "$status" -eq 0 ]; then
  cat "$log_path"
  exit 0
fi
cat "$log_path" 2>/dev/null || true
exit "$status"
