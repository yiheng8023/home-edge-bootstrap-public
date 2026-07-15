#!/bin/sh
# Host-side deploy helper for macOS/Linux/Git Bash.
set -u
validate_bool() {
  name="$1"
  value="$2"
  case "$value" in 0|1) ;; *) echo "deploy-merlin: invalid boolean $name=$value; expected 0 or 1" >&2; exit 2 ;; esac
}

router="${1:-${ROUTER:-}}"
if [ -z "$router" ]; then
  echo "usage: sh scripts/deploy-merlin.sh <ssh-user>@<router-ip>" >&2
  echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
  exit 2
fi

remote_dir="${REMOTE_DIR:-/jffs/home-edge-bootstrap}"
apply="${APPLY:-0}"
runtime_install="${BOOTSTRAP_INSTALL_RUNTIME:-0}"
replace_runtime="${BOOTSTRAP_REPLACE_RUNTIME:-0}"
replace_core="${BOOTSTRAP_REPLACE_CORE:-0}"
include_bundle="${INCLUDE_BUNDLE:-0}"
validate_bool APPLY "$apply"
validate_bool BOOTSTRAP_INSTALL_RUNTIME "$runtime_install"
validate_bool BOOTSTRAP_REPLACE_RUNTIME "$replace_runtime"
validate_bool BOOTSTRAP_REPLACE_CORE "$replace_core"
validate_bool INCLUDE_BUNDLE "$include_bundle"
known_hosts_file="${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}"
ssh_timeout="${SSH_CONNECT_TIMEOUT_SEC:-8}"
ssh_opts="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=$ssh_timeout -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts_file}"
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
archive_items="README.md README.zh-CN.md bootstrap.sh adapters config docs scripts"
[ "$include_bundle" = "1" ] || [ "$runtime_install" = "1" ] && archive_items="$archive_items bundle"
deploy_stage=""
cleanup_host_stage() {
  [ -z "$deploy_stage" ] || rm -rf "$deploy_stage"
}
trap cleanup_host_stage EXIT HUP INT TERM

case "$remote_dir" in
  /jffs/?*) ;;
  /jffs|/jffs/) echo "deploy-merlin: remote dir must not be the JFFS root" >&2; exit 2 ;;
  *) echo "deploy-merlin: remote dir must be under /jffs: $remote_dir" >&2; exit 2 ;;
esac
case "$remote_dir" in
  *[!A-Za-z0-9_./-]*) echo "deploy-merlin: remote dir contains unsupported characters: $remote_dir" >&2; exit 2 ;;
esac
remote_leaf=${remote_dir#/jffs/}
case "$remote_leaf" in
  ""|.|..|*/*) echo "deploy-merlin: remote dir must be one concrete directory below /jffs" >&2; exit 2 ;;
esac

host_bundle_verified=0
if [ "$runtime_install" = "1" ]; then
  sh "$repo/scripts/verify-bundle.sh" "$repo/bundle" || {
    echo "deploy-merlin: local offline bundle verification failed" >&2
    exit 1
  }
  host_bundle_verified=1
fi

if [ "$apply" != "1" ]; then
  echo "deploy_state=plan"
  echo "apply_required=1"
  echo "router=$router"
  echo "remote_dir=$remote_dir"
  echo "include_bundle=$([ "$include_bundle" = "1" ] || [ "$runtime_install" = "1" ] && echo 1 || echo 0)"
  echo "install_runtime=$runtime_install"
  echo "replace_runtime=$replace_runtime"
  echo "replace_core=$replace_core"
  echo "next_action=rerun with APPLY=1 after reviewing this plan"
  exit 0
fi

mkdir -p "$(dirname "$known_hosts_file")"

mode="BOOTSTRAP_APPLY=1"
[ "$runtime_install" = "1" ] && mode="$mode BOOTSTRAP_INSTALL_RUNTIME=1 BOOTSTRAP_BUNDLE_HOST_VERIFIED=$host_bundle_verified"
[ "$replace_runtime" = "1" ] && mode="$mode BOOTSTRAP_REPLACE_RUNTIME=1"
[ "$replace_core" = "1" ] && mode="$mode BOOTSTRAP_REPLACE_CORE=1"

remote_script='
set -eu
remote_dir="__REMOTE_DIR__"
staging="${remote_dir}.tmp.$$"
previous="${remote_dir}.prev"
lock_dir="/tmp/home-edge-bootstrap-write.lock"
failed_dir="${remote_dir}.failed.$(date +%Y%m%d%H%M%S).$$"
lock_held=0

for protected_path in "$remote_dir" "$staging" "$previous"; do
  [ ! -L "$protected_path" ] || {
    echo "deploy-merlin: refusing symbolic-link deployment path: $protected_path" >&2
    exit 1
  }
done

cleanup_deploy() {
  rm -rf "$staging" 2>/dev/null || true
  if [ "$lock_held" = "1" ]; then
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}
handle_deploy_signal() {
  cleanup_deploy
  trap - EXIT
  exit 130
}
trap cleanup_deploy EXIT
trap handle_deploy_signal HUP INT TERM

acquire_deploy_lock() {
  if ! mkdir "$lock_dir" 2>/dev/null; then
    owner_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      operation=$(cat "$lock_dir/operation" 2>/dev/null || echo unknown)
      echo "deploy-merlin: global write lock held by pid=$owner_pid operation=$operation" >&2
      exit 1
    fi
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || { echo "deploy-merlin: stale deployment lock cannot be cleared" >&2; exit 1; }
    mkdir "$lock_dir" 2>/dev/null || { echo "deploy-merlin: deployment lock was reacquired" >&2; exit 1; }
    echo "deploy-merlin: recovered stale deployment lock" >&2
  fi
  lock_held=1
  date +%s >"$lock_dir/started_at" || { echo "deploy-merlin: cannot record write lock start" >&2; exit 1; }
  printf "%s\n" "$$" >"$lock_dir/pid" || { echo "deploy-merlin: cannot record write lock owner" >&2; exit 1; }
  printf "%s\n" deploy >"$lock_dir/operation" || { echo "deploy-merlin: cannot record write operation" >&2; exit 1; }
}

preserve_local_state() {
  prev="$1"
  current="$2"
  [ -d "$prev" ] || return 0
  for item in SUBSCRIPTION.local policy.local; do
    [ -e "$prev/$item" ] || continue
    cp -p "$prev/$item" "$current/$item"
  done
  for dir in cache backups; do
    [ -d "$prev/$dir" ] || continue
    rm -rf "$current/$dir"
    cp -a "$prev/$dir" "$current/$dir"
  done
}

rollback_deploy() {
  restored=0
  [ -d "$remote_dir" ] && mv "$remote_dir" "$failed_dir"
  if [ -d "$previous" ]; then
    mv "$previous" "$remote_dir"
    restored=1
  fi
  if [ -f "$remote_dir/bootstrap.sh" ]; then
    if ! BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 sh "$remote_dir/bootstrap.sh" >/dev/null 2>&1; then
      echo "deploy-merlin: WARN previous kit was restored but its bootstrap replay failed" >&2
    fi
  fi
  [ "$restored" = "1" ] && rm -rf "$failed_dir"
}

acquire_deploy_lock
rm -rf "$staging"
mkdir -p "$staging"
tar -xzf - -C "$staging"
[ -s "$staging/bootstrap.sh" ] || { echo "deploy-merlin: staged kit is incomplete" >&2; exit 1; }
rm -rf "$previous"
[ ! -d "$remote_dir" ] || mv "$remote_dir" "$previous"
if ! mv "$staging" "$remote_dir"; then
  [ ! -d "$previous" ] || mv "$previous" "$remote_dir"
  exit 1
fi
if ! preserve_local_state "$previous" "$remote_dir"; then
  rollback_deploy
  echo "deploy-merlin: local state preservation failed; previous kit restored" >&2
  exit 1
fi
if ! (cd "$remote_dir" && HOME_EDGE_WRITE_LOCK_HELD=1 __MODE__ sh bootstrap.sh); then
  rollback_deploy
  echo "deploy-merlin: bootstrap failed; previous kit restored" >&2
  exit 1
fi
echo "deploy_state=applied"
echo "rollback_available=$([ -d "$previous" ] && echo 1 || echo 0)"
'
remote_script=$(printf '%s' "$remote_script" | sed "s#__REMOTE_DIR__#$remote_dir#g; s#__MODE__#$mode#g")

# Stage first so provenance hashes the exact bytes sent to the router.
deploy_stage=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-deploy-stage.XXXXXX") || exit 1
# shellcheck disable=SC2086
tar -C "$repo" -cf - $archive_items | tar -C "$deploy_stage" -xf -
sh "$repo/scripts/new-deployment-provenance.sh" "$deploy_stage" "$repo" || exit 1
[ -s "$deploy_stage/DEPLOYMENT-CONTENT-SHA256SUMS" ] || { echo "deploy-merlin: provenance generation failed" >&2; exit 1; }
tar -C "$deploy_stage" -czf - . |
  ssh $ssh_opts -- "$router" "$remote_script"
