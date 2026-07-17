#!/bin/sh
# Router-side rollback for Home Edge Bootstrap deployments. PLAN mode by default.
set -eu
umask 077

apply="${ROLLBACK_APPLY:-0}"
restore_runtime="${ROLLBACK_RUNTIME:-0}"
root="${HOME_EDGE_ROLLBACK_ROOT:-}"
install_dir="${ROLLBACK_INSTALL_DIR:-/jffs/home-edge-bootstrap}"
script_dir="${ROLLBACK_SCRIPT_DIR:-/jffs/scripts}"
shellcrash_dir="${ROLLBACK_SHELLCRASH_DIR:-/jffs/ShellCrash}"
state_root="${ROLLBACK_STATE_ROOT:-/jffs/home-edge-bootstrap-state}"
lock_dir="${ROLLBACK_LOCK_DIR:-/tmp/home-edge-bootstrap-write.lock}"

log() { echo "home-edge-rollback: $*"; }
die() { echo "home-edge-rollback: ERROR: $*" >&2; exit 1; }
case "$apply" in 0|1) ;; *) die "ROLLBACK_APPLY must be 0 or 1" ;; esac
case "$restore_runtime" in 0|1) ;; *) die "ROLLBACK_RUNTIME must be 0 or 1" ;; esac

validate_jffs_subpath() {
  name="$1"
  value="$2"
  case "$value" in
    /jffs/?*) ;;
    /jffs|/jffs/) die "$name must not be the JFFS root" ;;
    *) die "$name must be under /jffs" ;;
  esac
  case "$value" in
    *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) die "$name contains unsupported characters or path traversal" ;;
  esac
  leaf=${value#/jffs/}
  case "$leaf" in ""|.|..|*/*) die "$name must be one concrete directory below /jffs" ;; esac
}

validate_jffs_subpath ROLLBACK_INSTALL_DIR "$install_dir"
validate_jffs_subpath ROLLBACK_SCRIPT_DIR "$script_dir"
validate_jffs_subpath ROLLBACK_SHELLCRASH_DIR "$shellcrash_dir"
validate_jffs_subpath ROLLBACK_STATE_ROOT "$state_root"
case "$lock_dir" in /tmp/?*) ;; *) die "ROLLBACK_LOCK_DIR must be a concrete path under /tmp" ;; esac
case "$lock_dir" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) die "ROLLBACK_LOCK_DIR contains unsupported characters or path traversal" ;; esac

path_in_root() {
  case "$1" in
    /*) printf '%s%s\n' "$root" "$1" ;;
    *) printf '%s/%s\n' "$root" "$1" ;;
  esac
}

current_dir=$(path_in_root "$install_dir")
prev_dir=$(path_in_root "$install_dir.prev")
script_dir_path=$(path_in_root "$script_dir")
shellcrash_path=$(path_in_root "$shellcrash_dir")
state_root_path=$(path_in_root "$state_root")
runtime_backup_dir="$state_root_path/backups/runtime"

run() {
  if [ "$apply" = "1" ]; then
    "$@"
  else
    printf 'PLAN:'
    for arg in "$@"; do printf ' %s' "$arg"; done
    printf '\n'
  fi
}

release_lock() {
  [ -d "$lock_dir" ] || return 0
  rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
}

handle_signal() {
  log "interrupted; rollback can be rerun safely"
  exit 130
}

acquire_lock() {
  if [ "$apply" != "1" ]; then
    log "PLAN: acquire rollback lock $lock_dir"
    return 0
  fi
  if ! mkdir "$lock_dir" 2>/dev/null; then
    owner_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      operation=$(cat "$lock_dir/operation" 2>/dev/null || echo unknown)
      die "global write lock held by pid=$owner_pid operation=$operation"
    fi
    started=$(cat "$lock_dir/started_at" 2>/dev/null || true)
    now=$(date +%s)
    case "$started:$now" in *[!0-9:]*|:*|*:) age=0 ;; *) age=$((now - started)) ;; esac
    if [ -z "$owner_pid" ] && [ "$age" -le 1800 ]; then
      die "global write lock has no verifiable owner and lease has not expired"
    fi
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || die "cannot clear stale global write lock: $lock_dir"
    mkdir "$lock_dir" 2>/dev/null || die "global write lock was reacquired: $lock_dir"
  fi
  date +%s >"$lock_dir/started_at" || die "cannot record rollback lock start"
  printf '%s\n' "$$" >"$lock_dir/pid" || die "cannot record rollback lock owner"
  printf '%s\n' rollback >"$lock_dir/operation" || die "cannot record rollback operation"
  trap release_lock EXIT
  trap handle_signal HUP INT TERM
}

latest_dir() {
  pattern="$1"
  latest=""
  for candidate in $pattern; do
    [ -d "$candidate" ] || continue
    case "$candidate" in *.rollback-current.*) continue ;; esac
    latest="$candidate"
  done
  [ -n "$latest" ] && printf '%s\n' "$latest"
}

latest_file() {
  pattern="$1"
  latest=""
  for candidate in $pattern; do
    [ -f "$candidate" ] || continue
    case "$candidate" in *.rollback-current.*) continue ;; esac
    latest="$candidate"
  done
  [ -n "$latest" ] && printf '%s\n' "$latest"
}

restore_runtime_backup() {
  latest_shellcrash=$(latest_dir "$runtime_backup_dir/ShellCrash.*" || true)
  [ -n "$latest_shellcrash" ] || die "no ShellCrash runtime backup found under $runtime_backup_dir"
  latest_nat_start=$(latest_file "$runtime_backup_dir/nat-start.*" || true)

  ts=$(date +%Y%m%d%H%M%S)
  current_runtime_backup="$runtime_backup_dir/ShellCrash.rollback-current.$ts.$$"
  runtime_stage="$shellcrash_path.restore.$$"
  current_nat_start_backup="$runtime_backup_dir/nat-start.rollback-current.$ts.$$"

  if [ "$apply" != "1" ]; then
    run mkdir -p "$runtime_backup_dir"
    run mv "$latest_shellcrash" "$runtime_stage"
    [ -d "$shellcrash_path" ] && run mv "$shellcrash_path" "$current_runtime_backup"
    run mv "$runtime_stage" "$shellcrash_path"
    if [ -n "$latest_nat_start" ]; then
      run mkdir -p "$script_dir_path"
      [ -f "$script_dir_path/nat-start" ] && run cp "$script_dir_path/nat-start" "$current_nat_start_backup"
      run cp "$latest_nat_start" "$script_dir_path/nat-start"
    fi
    return 0
  fi

  mkdir -p "$runtime_backup_dir"
  [ ! -e "$runtime_stage" ] || die "runtime restore staging path already exists: $runtime_stage"
  mv "$latest_shellcrash" "$runtime_stage" || die "cannot stage ShellCrash runtime backup"
  current_runtime_moved=0
  if [ -d "$shellcrash_path" ]; then
    if ! mv "$shellcrash_path" "$current_runtime_backup"; then
      mv "$runtime_stage" "$latest_shellcrash" 2>/dev/null || true
      die "cannot back up the current ShellCrash runtime"
    fi
    current_runtime_moved=1
  fi
  if ! mv "$runtime_stage" "$shellcrash_path"; then
    [ "$current_runtime_moved" = "0" ] || mv "$current_runtime_backup" "$shellcrash_path" 2>/dev/null || true
    mv "$runtime_stage" "$latest_shellcrash" 2>/dev/null || true
    die "cannot activate the restored ShellCrash runtime; current runtime restored"
  fi

  if [ -n "$latest_nat_start" ]; then
    mkdir -p "$script_dir_path"
    nat_start_had_current=0
    if [ -f "$script_dir_path/nat-start" ]; then
      cp "$script_dir_path/nat-start" "$current_nat_start_backup" || die "cannot back up current nat-start"
      nat_start_had_current=1
    fi
    if ! cp "$latest_nat_start" "$script_dir_path/nat-start"; then
      [ "$nat_start_had_current" = "0" ] || cp "$current_nat_start_backup" "$script_dir_path/nat-start" 2>/dev/null || true
      die "cannot restore nat-start; current file restored"
    fi
  fi
}

reapply_restored_kit() {
  restored_kit="$current_dir"
  [ "$apply" = "1" ] || restored_kit="$prev_dir"
  [ -f "$restored_kit/bootstrap.sh" ] || die "restored kit does not contain bootstrap.sh"
  if [ "$apply" = "1" ]; then
    HOME_EDGE_ROLLBACK_ROOT="$root" HOME_EDGE_WRITE_LOCK_HELD=1 BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 sh "$current_dir/bootstrap.sh"
  else
    log "PLAN: reapply restored kit with BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0"
  fi
}

log "mode=$([ "$apply" = "1" ] && echo apply || echo plan)"
log "install_dir=$install_dir"
log "restore_runtime=$restore_runtime"
log "runtime_backup_dir=$state_root/backups/runtime"

[ -d "$prev_dir" ] || die "previous deployment not found: $install_dir.prev"
if [ "$apply" = "1" ]; then
  for protected_path in "$current_dir" "$prev_dir" "$script_dir_path" "$shellcrash_path" "$state_root_path"; do
    [ ! -L "$protected_path" ] || die "rollback path must not be a symbolic link: $protected_path"
  done
fi

acquire_lock

ts=$(date +%Y%m%d%H%M%S)
rollback_dir="$current_dir.rollback.$ts.$$"

if [ -d "$current_dir" ]; then
  run mv "$current_dir" "$rollback_dir"
else
  log "current deployment directory is missing; restoring previous directory only"
fi
run mv "$prev_dir" "$current_dir"

if [ "$restore_runtime" = "1" ]; then
  restore_runtime_backup
fi

reapply_restored_kit

log "rollback_state=ready"
log "restored_dir=$install_dir"
log "rollback_backup=$rollback_dir"
