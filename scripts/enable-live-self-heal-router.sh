#!/bin/sh
# Router-side transaction for enabling live self-heal.
set -eu
umask 077

root="${HOME_EDGE_ENABLE_ROOT:-}"
max_backups="${ENABLE_LIVE_MAX_BACKUPS:-5}"
lock_dir="${HOME_EDGE_WRITE_LOCK_DIR:-/tmp/home-edge-bootstrap-write.lock}"
lock_stale_sec="${HOME_EDGE_WRITE_LOCK_STALE_SEC:-1800}"
lock_acquired=0

path_in_root() {
  case "$1" in
    /*) printf '%s%s\n' "$root" "$1" ;;
    *) printf '%s/%s\n' "$root" "$1" ;;
  esac
}

policy_rel="${ENABLE_POLICY_PATH:-/jffs/scripts/home-edge-policy.env}"
local_policy_rel="${ENABLE_LOCAL_POLICY_PATH:-/jffs/home-edge-bootstrap-state/policy.local}"
cron_wrapper_rel="${ENABLE_CRON_WRAPPER_PATH:-/jffs/scripts/home-edge-self-heal-cron.sh}"
reconciler_rel="${ENABLE_RECONCILER_PATH:-/jffs/scripts/home-edge-reconcile-self-heal.sh}"
services_start_rel="${ENABLE_SERVICES_START_PATH:-/jffs/scripts/services-start}"
for managed_path in "$policy_rel" "$cron_wrapper_rel" "$reconciler_rel" "$services_start_rel"; do
  case "$managed_path" in
    /jffs/scripts/?*) ;;
    *) echo "enable-live-self-heal: ERROR: managed paths must remain below /jffs/scripts" >&2; exit 1 ;;
  esac
  case "$managed_path" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) echo "enable-live-self-heal: ERROR: unsafe managed path" >&2; exit 1 ;; esac
done
case "$local_policy_rel" in
  /jffs/home-edge-bootstrap-state/policy.local) ;;
  *) echo "enable-live-self-heal: ERROR: local policy must use the stable state root" >&2; exit 1 ;;
esac
policy=$(path_in_root "$policy_rel")
local_policy=$(path_in_root "$local_policy_rel")
cron_wrapper=$(path_in_root "$cron_wrapper_rel")
reconciler=$(path_in_root "$reconciler_rel")
services_start=$(path_in_root "$services_start_rel")
tmp_policy=""
backup=""
committed=0
local_policy_existed=0
surface_snapshot=""
hook_existed=0

log() { echo "enable-live-self-heal: $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

case "$lock_dir" in /tmp/?*) ;; *) die "HOME_EDGE_WRITE_LOCK_DIR must remain below /tmp" ;; esac
case "$lock_dir" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) die "unsafe HOME_EDGE_WRITE_LOCK_DIR" ;; esac
case "$lock_stale_sec" in ""|*[!0-9]*|0) lock_stale_sec=1800 ;; esac

release_lock() {
  if [ "$lock_acquired" = "1" ]; then
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}

acquire_lock() {
  if ! mkdir "$lock_dir" 2>/dev/null; then
    owner_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      operation=$(cat "$lock_dir/operation" 2>/dev/null || echo unknown)
      die "global write lock held by pid=$owner_pid operation=$operation"
    fi
    started=$(cat "$lock_dir/started_at" 2>/dev/null || true)
    now=$(date +%s)
    case "$started:$now" in *[!0-9:]*|:*|*:) age=0 ;; *) age=$((now - started)) ;; esac
    if [ -z "$owner_pid" ] && [ "$age" -le "$lock_stale_sec" ]; then
      die "global write lock has no verifiable owner and lease has not expired"
    fi
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || die "stale global write lock cannot be cleared"
    mkdir "$lock_dir" 2>/dev/null || die "global write lock was reacquired"
  fi
  lock_acquired=1
  date +%s >"$lock_dir/started_at" || die "cannot record write lock start"
  printf '%s\n' "$$" >"$lock_dir/pid" || die "cannot record write lock owner"
  printf '%s\n' enable-live-self-heal >"$lock_dir/operation" || die "cannot record write operation"
}

cleanup() {
  [ -z "$tmp_policy" ] || rm -f "$tmp_policy" 2>/dev/null || true
  [ -z "$surface_snapshot" ] || rm -rf "$surface_snapshot" 2>/dev/null || true
  release_lock
}
trap cleanup EXIT
trap 'cleanup; exit 130' HUP INT TERM

prune_backups() {
  case "$max_backups" in ""|*[!0-9]*) max_backups=5 ;; esac
  [ "$max_backups" -gt 0 ] || return 0
  count=0
  for candidate in $(ls -1t "${local_policy}.bak."* 2>/dev/null); do
    count=$((count + 1))
    [ "$count" -le "$max_backups" ] || rm -f "$candidate"
  done
}

restore_policy() {
  if [ "$local_policy_existed" = "0" ]; then
    rm -f "$local_policy" || return 1
    return 0
  fi
  [ -n "$backup" ] && [ -f "$backup" ] || return 1
  cp -p "$backup" "$tmp_policy" || return 1
  chmod 600 "$tmp_policy" 2>/dev/null || true
  mv "$tmp_policy" "$local_policy"
}

snapshot_registration_surface() {
  surface_snapshot=$(mktemp -d "/tmp/home-edge-enable-snapshot.XXXXXX") || return 1
  if [ -e "$services_start" ]; then
    [ -f "$services_start" ] && [ ! -L "$services_start" ] || return 1
    cp -p "$services_start" "$surface_snapshot/services-start" || return 1
    hook_existed=1
  fi
  cru l 2>/dev/null | grep -F '#home_edge_selfheal#' >"$surface_snapshot/cron" || true
}

restore_registration_surface() {
  if [ "$hook_existed" = "1" ]; then
    cp -p "$surface_snapshot/services-start" "$services_start" || return 1
  else
    rm -f "$services_start" || return 1
  fi
  cru d home_edge_selfheal >/dev/null 2>&1 || true
  while IFS= read -r prior_line; do
    [ -n "$prior_line" ] || continue
    prior_job=${prior_line% #home_edge_selfheal#}
    cru a home_edge_selfheal "$prior_job" >/dev/null 2>&1 || return 1
  done <"$surface_snapshot/cron"
  current_matches=$(cru l 2>/dev/null | grep -F '#home_edge_selfheal#' || true)
  prior_matches=$(cat "$surface_snapshot/cron")
  [ "$current_matches" = "$prior_matches" ]
}

acquire_lock
[ -s "$policy" ] || die "missing policy: $policy"
[ -s "$cron_wrapper" ] || die "missing cron wrapper: $cron_wrapper"
[ -s "$reconciler" ] || die "missing lifecycle reconciler: $reconciler"
mkdir -p "$(dirname "$local_policy")" || die "cannot prepare local policy directory"
snapshot_registration_surface || die "cannot snapshot lifecycle registration surface"
tmp_policy=$(mktemp "${local_policy}.tmp.XXXXXX") || die "cannot allocate temporary policy"
[ ! -e "$local_policy" ] || local_policy_existed=1
[ -e "$local_policy" ] || : >"$local_policy"
chmod 600 "$local_policy" 2>/dev/null || true

backup="${local_policy}.bak.$(date +%Y%m%d%H%M%S).$$"
cp -p "$local_policy" "$backup" || die "cannot back up local policy"

sed '/^HEAL_CRON_DRY_RUN=/d;/^: "${HEAL_CRON_DRY_RUN:=/d' "$local_policy" >"$tmp_policy" ||
  die "cannot stage local policy"
printf 'HEAL_CRON_DRY_RUN=0\n' >>"$tmp_policy" || die "cannot stage live policy"
chmod 600 "$tmp_policy" 2>/dev/null || true
mv "$tmp_policy" "$local_policy" || die "cannot commit live policy"
committed=1

if HOME_EDGE_RECONCILE_ROOT="$root" HOME_EDGE_WRITE_LOCK_HELD=1 sh "$reconciler" --install &&
   HOME_EDGE_WRITE_LOCK_HELD=1 sh "$cron_wrapper"; then
  log "enable_live_state=enabled"
  log "local_policy=$local_policy"
  log "backup=$backup"
  prune_backups
  exit 0
fi

policy_restored=0
surface_restored=0
if [ "$committed" = "1" ] && restore_policy; then policy_restored=1; fi
if restore_registration_surface; then surface_restored=1; fi
if [ "$policy_restored" = "1" ] && [ "$surface_restored" = "1" ]; then
  log "enable_live_state=rolled_back"
  log "backup=$backup"
  die "initial live self-heal run failed; restored previous local policy"
fi

log "enable_live_state=rollback_failed"
die "initial live self-heal run failed and transaction rollback failed"
