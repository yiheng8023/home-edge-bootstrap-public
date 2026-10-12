#!/bin/sh
# Fresh, read-only adapter inventory. Historical logs are never accepted as input.
set -u
router=""
remote_dir=${REMOTE_DIR:-/jffs/home-edge-bootstrap}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --remote-dir) shift; [ "$#" -gt 0 ] || exit 2; remote_dir=$1 ;;
    --help|-h) echo 'usage: sh scripts/check-project-installation.sh [--remote-dir /jffs/name] user@router'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) [ -z "$router" ] || { echo 'unexpected router argument' >&2; exit 2; }; router=$1 ;;
  esac
  shift
done
router=${router:-${ROUTER:-}}
printf '%s\n' "$router" | grep -Eq '^[A-Za-z0-9_.-]+@[A-Za-z0-9][A-Za-z0-9.-]*$' || exit 2
case "$router" in *@*..*|*@.*|*@*.) exit 2 ;; esac
case "$remote_dir" in /jffs/?*) ;; *) exit 2 ;; esac
leaf=${remote_dir#/jffs/}
case "$leaf" in ''|.|..|*/*|*[!A-Za-z0-9_.-]*) exit 2 ;; esac
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
unknown() {
  printf 'project_install_schema=1\nproject_install_router=%s\nproject_install_state=unknown\nproject_install_reason=%s\nproject_install_path=%s\nproject_install_replace_allowed=0\n' "$router" "$1" "$remote_dir"
}
library="$repo/adapters/merlin/lib/installation-state.sh"
[ -r "$library" ] || { unknown observer_unavailable; exit 1; }
library_text=$(cat "$library") || { unknown observer_unavailable; exit 1; }
ssh_command=${HOME_EDGE_SSH_COMMAND:-ssh}
known_hosts=${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}
mkdir -p "$(dirname "$known_hosts")" || { unknown host_trust_path_unavailable; exit 1; }
ssh_opts=${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts}
payload="$library_text
HOME_EDGE_INSTALLATION_DIR='$remote_dir'
HOME_EDGE_INSTALLATION_ROUTER='$router'
HOME_EDGE_INSTALLATION_FIXTURE_ROOT=''
home_edge_inspect_installation"
# shellcheck disable=SC2086
if output=$(printf '%s\n' "$payload" | "$ssh_command" $ssh_opts -- "$router" 'sh -s' 2>/dev/null); then :
else unknown probe_failed; exit 1; fi
value() { printf '%s\n' "$output" | awk -F= -v key="$1" '$1 == key { print substr($0, index($0,"=")+1) }'; }
if [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" != 6 ] ||
   [ "$(value project_install_schema)" != 1 ] ||
   [ "$(value project_install_path)" != "$remote_dir" ]; then unknown malformed_observation; exit 1; fi
[ "$(value project_install_router)" = "$router" ] || { unknown target_mismatch; exit 1; }
state=$(value project_install_state)
reason=$(value project_install_reason)
allowed=$(value project_install_replace_allowed)
case "$state" in installed|not_installed|partial|unknown) ;; *) unknown malformed_observation; exit 1 ;; esac
case "$reason" in ''|*[!a-z0-9_]*) unknown malformed_observation; exit 1 ;; esac
case "$allowed" in 0|1) ;; *) unknown malformed_observation; exit 1 ;; esac
case "$state:$allowed" in unknown:1|not_installed:1) unknown malformed_observation; exit 1 ;; esac
printf '%s\n' "$output"
[ "$state" != unknown ] || exit 1
