#!/bin/sh
# Host-side plan/apply wrapper for safe Merlin project decommission.
set -u

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
router=${ROUTER:-}
apply=0
confirmation=
known_hosts_file=${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}
ssh_timeout=${SSH_CONNECT_TIMEOUT_SEC:-8}

usage() {
  echo "usage: sh scripts/decommission-merlin.sh <ssh-user>@<router-ip> [--apply --confirm DECOMMISSION] [--known-hosts-file <path>]" >&2
}
die_usage() { echo "decommission-merlin: ERROR: $*" >&2; usage; exit 2; }
valid_router() {
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_.-]+@[A-Za-z0-9][A-Za-z0-9.-]*$' || return 1
  case "$1" in *@*..*|*@.*|*@*.) return 1 ;; esac
  return 0
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    --confirm)
      shift
      [ "$#" -gt 0 ] || die_usage "--confirm requires a value"
      confirmation=$1
      ;;
    --known-hosts-file)
      shift
      [ "$#" -gt 0 ] || die_usage "--known-hosts-file requires a value"
      known_hosts_file=$1
      ;;
    -*) die_usage "unknown option: $1" ;;
    *)
      [ -z "$router" ] || die_usage "router target was provided more than once"
      router=$1
      ;;
  esac
  shift
done

[ -n "$router" ] || die_usage "router target is required"
valid_router "$router" || die_usage "invalid router target: $router"
if [ "$apply" = 1 ] && [ "$confirmation" != DECOMMISSION ]; then
  echo "decommission-merlin: ERROR: --apply requires --confirm DECOMMISSION" >&2
  exit 2
fi
if [ "$apply" = 0 ] && [ -n "$confirmation" ]; then
  die_usage "--confirm is valid only with --apply"
fi
case "$known_hosts_file" in /*) ;; *) die_usage "known-hosts file must be an absolute path" ;; esac
case "$known_hosts_file" in *[!A-Za-z0-9_./-]*|*'/../'*|*/..|*'/./'*|*/.|*'//'*) die_usage "known-hosts file contains an unsafe path" ;; esac
case "$ssh_timeout" in ''|*[!0-9]*|0) die_usage "SSH_CONNECT_TIMEOUT_SEC must be a positive integer" ;; esac

for source in "$repo/scripts/migrate-router-state.sh" "$repo/scripts/decommission-router-state.sh"; do
  [ -f "$source" ] && [ ! -L "$source" ] || { echo "decommission-merlin: ERROR: missing reviewed source: $source" >&2; exit 1; }
done
command -v tar >/dev/null 2>&1 || { echo "decommission-merlin: ERROR: tar is required" >&2; exit 1; }
command -v ssh >/dev/null 2>&1 || { echo "decommission-merlin: ERROR: ssh is required" >&2; exit 1; }
mkdir -p "$(dirname "$known_hosts_file")" || exit 1

ssh_opts="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=$ssh_timeout -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts_file}"
remote_script='set -eu
work=/tmp/home-edge-decommission.$$
cleanup() { rm -rf "$work"; }
handle_signal() { cleanup; trap - EXIT; exit 130; }
trap cleanup EXIT
trap handle_signal HUP INT TERM
mkdir -m 700 "$work"
tar -xzf - -C "$work"
[ -f "$work/migrate-router-state.sh" ] && [ ! -L "$work/migrate-router-state.sh" ]
[ -f "$work/decommission-router-state.sh" ] && [ ! -L "$work/decommission-router-state.sh" ]
HOME_EDGE_STATE_MIGRATOR="$work/migrate-router-state.sh" \
DECOMMISSION_APPLY=__APPLY__ \
DECOMMISSION_CONFIRMATION=__CONFIRMATION__ \
sh "$work/decommission-router-state.sh"'
remote_script=$(printf '%s' "$remote_script" | sed "s/__APPLY__/$apply/g; s/__CONFIRMATION__/$confirmation/g")

tar -C "$repo/scripts" -czf - migrate-router-state.sh decommission-router-state.sh |
  ssh $ssh_opts -- "$router" "$remote_script"
exit $?
