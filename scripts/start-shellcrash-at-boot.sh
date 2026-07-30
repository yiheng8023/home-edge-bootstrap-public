#!/bin/sh
# Conservative Asuswrt-Merlin boot recovery for an installed ShellCrash runtime.
set -u
umask 077

crash_dir="${HOME_EDGE_SHELLCRASH_DIR:-/jffs/ShellCrash}"
state_dir="${HOME_EDGE_STATE_ROOT:-/jffs/home-edge-bootstrap-state}"
# Asuswrt-Merlin's native ShellCrash nat-start path waits 60 seconds.
# Run later so this helper is a fallback instead of racing the native start.
delay="${HOME_EDGE_SHELLCRASH_BOOT_DELAY:-90}"
lock_dir="${HOME_EDGE_SHELLCRASH_BOOT_LOCK:-/tmp/home-edge-shellcrash-boot.lock}"
log_file="${HOME_EDGE_SHELLCRASH_BOOT_LOG:-/tmp/home-edge-shellcrash-boot.log}"
protected_core="${HOME_EDGE_PROTECTED_CORE:-$state_dir/runtime/mihomo-linux-arm64.gz}"
core_link="$crash_dir/CrashCore.gz"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$log_file"
}

case "$crash_dir:$state_dir:$lock_dir:$log_file:$protected_core" in
  *[!A-Za-z0-9_./:-]*|*/../*|*/..|*/./*|*/.) log "state=blocked reason=unsafe_path"; exit 1 ;;
esac
case "$crash_dir:$state_dir:$lock_dir:$log_file:$protected_core" in
  /*:/*:/*:/*:/*) ;;
  *) log "state=blocked reason=non_absolute_path"; exit 1 ;;
esac
case "$delay" in
  ''|*[!0-9]*) log "state=blocked reason=invalid_delay"; exit 1 ;;
esac

[ -x "$crash_dir/start.sh" ] || {
  log "state=blocked reason=start_script_missing"
  exit 1
}

startup_tasks_safe() {
  for task_file in "$crash_dir/task/bfstart" "$crash_dir/task/afstart"; do
    [ -s "$task_file" ] || continue
    if grep -Eq '/task\.sh[[:space:]]+(101|111|112|113)([[:space:]]|$)' "$task_file"; then
      return 1
    fi
  done
}

restore_core_link() {
  [ -e "$core_link" ] && return 0
  [ -s "$protected_core" ] || return 0
  ln "$protected_core" "$core_link" 2>/dev/null ||
    cp -p "$protected_core" "$core_link" ||
    return 1
  chmod 600 "$core_link" || return 1
  return 0
}

[ -e "$crash_dir/.dis_startup" ] && {
  log "state=skipped reason=manually_disabled"
  exit 0
}
[ -e "$crash_dir/.start_error" ] && {
  log "state=skipped reason=prior_start_error"
  exit 0
}
startup_tasks_safe || {
  log "state=blocked reason=unsafe_automatic_tasks"
  exit 1
}

if pidof CrashCore >/dev/null 2>&1; then
  log "state=ready reason=already_running"
  exit 0
fi

[ "$delay" -gt 0 ] && sleep "$delay"

[ -e "$crash_dir/.dis_startup" ] && {
  log "state=skipped reason=manually_disabled_after_delay"
  exit 0
}
[ -e "$crash_dir/.start_error" ] && {
  log "state=skipped reason=prior_start_error_after_delay"
  exit 0
}
startup_tasks_safe || {
  log "state=blocked reason=unsafe_automatic_tasks_after_delay"
  exit 1
}

mkdir "$lock_dir" 2>/dev/null || {
  log "state=skipped reason=start_already_in_progress"
  exit 0
}

cleanup() {
  rmdir "$lock_dir" 2>/dev/null || true
}
handle_signal() {
  cleanup
  trap - EXIT
  exit 130
}
trap cleanup EXIT
trap handle_signal HUP INT TERM

if pidof CrashCore >/dev/null 2>&1; then
  log "state=ready reason=started_by_peer"
  exit 0
fi

restore_core_link || {
  log "state=blocked reason=protected_core_restore_failed"
  exit 1
}

log "state=starting reason=boot_recovery"
if sh "$crash_dir/start.sh" start >>"$log_file" 2>&1; then
  log "state=dispatched"
else
  rc=$?
  log "state=failed reason=start_dispatch exit_code=$rc"
  exit "$rc"
fi
