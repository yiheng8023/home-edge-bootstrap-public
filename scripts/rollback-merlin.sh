#!/bin/sh
# Host-side rollback command for macOS/Linux/Git Bash.
set -u

router=""
apply=0
runtime=0
remote_dir="${REMOTE_DIR:-/jffs/home-edge-bootstrap}"
known_hosts_file="${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    --runtime) runtime=1 ;;
    --remote-dir)
      shift
      remote_dir="${1:-}"
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      exit 2
      ;;
    *)
      router="$1"
      ;;
  esac
  shift || break
done

router="${router:-${ROUTER:-}}"
[ -n "$router" ] || { echo "usage: sh scripts/rollback-merlin.sh <ssh-user>@<router-ip> [--apply] [--runtime]" >&2; exit 2; }
case "$remote_dir" in
  /jffs/?*) ;;
  /jffs|/jffs/) echo "ERROR: --remote-dir must not be the JFFS root." >&2; exit 2 ;;
  *) echo "ERROR: --remote-dir must be under /jffs." >&2; exit 2 ;;
esac
case "$remote_dir" in
  *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) echo "ERROR: --remote-dir contains unsupported characters or path segments." >&2; exit 2 ;;
esac

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
rollback_script="$script_dir/rollback-router-state.sh"
[ -r "$rollback_script" ] || { echo "ERROR: missing $rollback_script" >&2; exit 1; }

mkdir -p "$(dirname "$known_hosts_file")"
ssh_opts="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts_file}"
remote="base64 -d | ROLLBACK_INSTALL_DIR='$remote_dir' ROLLBACK_APPLY='$apply' ROLLBACK_RUNTIME='$runtime' sh -s"

# shellcheck disable=SC2086
base64 < "$rollback_script" | ssh $ssh_opts -- "$router" "$remote"
