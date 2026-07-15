#!/bin/sh
# Reconcile project-owned self-heal cron and Merlin boot registration.
set -eu
umask 077

root="${HOME_EDGE_RECONCILE_ROOT:-}"
policy_rel="${HOME_EDGE_POLICY_PATH:-/jffs/scripts/home-edge-policy.env}"
local_policy_rel="${HOME_EDGE_LOCAL_POLICY_PATH:-/jffs/scripts/home-edge-policy.local}"
wrapper_rel="${HOME_EDGE_CRON_WRAPPER_PATH:-/jffs/scripts/home-edge-self-heal-cron.sh}"
reconciler_rel="${HOME_EDGE_RECONCILER_PATH:-/jffs/scripts/home-edge-reconcile-self-heal.sh}"
services_start_rel="${HOME_EDGE_SERVICES_START_PATH:-/jffs/scripts/services-start}"
job_name="${HOME_EDGE_CRON_JOB_NAME:-home_edge_selfheal}"
begin_marker='# BEGIN home-edge-bootstrap self-heal lifecycle'
end_marker='# END home-edge-bootstrap self-heal lifecycle'
tmp_hook=""
lock_dir="${HOME_EDGE_WRITE_LOCK_DIR:-/tmp/home-edge-bootstrap-write.lock}"
lock_stale_sec="${HOME_EDGE_WRITE_LOCK_STALE_SEC:-1800}"
write_lock_already_held="${HOME_EDGE_WRITE_LOCK_HELD:-0}"
lock_acquired=0

log() { printf '%s\n' "lifecycle-reconcile: $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

case "$root" in
  "") ;;
  /*) case "$root" in *[!A-Za-z0-9_./:-]*|*/../*|*/..|*/./*|*/.) die "unsafe HOME_EDGE_RECONCILE_ROOT" ;; esac ;;
  *) die "HOME_EDGE_RECONCILE_ROOT must be empty or absolute" ;;
esac

path_in_root() {
  case "$1" in
    /*) printf '%s%s\n' "$root" "$1" ;;
    *) printf '%s/%s\n' "$root" "$1" ;;
  esac
}

for managed_path in "$policy_rel" "$local_policy_rel" "$wrapper_rel" "$reconciler_rel" "$services_start_rel"; do
  case "$managed_path" in
    /jffs/scripts/?*) ;;
    *) die "managed paths must remain below /jffs/scripts" ;;
  esac
  case "$managed_path" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) die "unsafe managed path" ;; esac
done
case "$job_name" in ""|*[!A-Za-z0-9_-]*) die "unsafe cron job name" ;; esac
case "$write_lock_already_held" in 0|1) ;; *) die "HOME_EDGE_WRITE_LOCK_HELD must be 0 or 1" ;; esac
case "$lock_dir" in /tmp/?*) ;; *) die "HOME_EDGE_WRITE_LOCK_DIR must remain below /tmp" ;; esac
case "$lock_dir" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) die "unsafe HOME_EDGE_WRITE_LOCK_DIR" ;; esac
case "$lock_stale_sec" in ""|*[!0-9]*|0) lock_stale_sec=1800 ;; esac

policy=$(path_in_root "$policy_rel")
local_policy=$(path_in_root "$local_policy_rel")
wrapper=$(path_in_root "$wrapper_rel")
reconciler=$(path_in_root "$reconciler_rel")
services_start=$(path_in_root "$services_start_rel")

cleanup() {
  [ -z "$tmp_hook" ] || rm -f "$tmp_hook" "${tmp_hook}.content" "${tmp_hook}.assembled" 2>/dev/null || true
  if [ "$lock_acquired" = "1" ]; then
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' HUP INT TERM

acquire_lock() {
  [ "$write_lock_already_held" != "1" ] || { log "inherited global write lock"; return 0; }
  mkdir -p "$(dirname "$lock_dir")" 2>/dev/null || die "cannot prepare global write lock parent"
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
  printf '%s\n' lifecycle-reconcile >"$lock_dir/operation" || die "cannot record write operation"
}

load_policy() {
  HEAL_CRON_DRY_RUN=1
  HEAL_CRON_SCHEDULE='*/3 * * * *'
  [ ! -r "$policy" ] || . "$policy"
  [ ! -r "$local_policy" ] || . "$local_policy"
  schedule=${HEAL_CRON_SCHEDULE:-'*/3 * * * *'}
  dry_run=${HEAL_CRON_DRY_RUN:-1}

  old_ifs=$IFS
  IFS=' '
  set -f
  # shellcheck disable=SC2086
  set -- $schedule
  set +f
  IFS=$old_ifs
  [ "$#" -eq 5 ] || die "HEAL_CRON_SCHEDULE must contain five fields"
  for field in "$@"; do
    printf '%s\n' "$field" | grep -Eq '^[-0-9*/,]+$' || die "HEAL_CRON_SCHEDULE contains unsafe characters"
  done
  case "$dry_run" in 0|1) ;; *) die "HEAL_CRON_DRY_RUN must be 0 or 1" ;; esac
}

hook_marker_counts() {
  hook_begin_count=0
  hook_end_count=0
  if [ -f "$services_start" ]; then
    hook_begin_count=$(grep -Fxc "$begin_marker" "$services_start" 2>/dev/null || true)
    hook_end_count=$(grep -Fxc "$end_marker" "$services_start" 2>/dev/null || true)
  fi
}

boot_hook_state() {
  hook_marker_counts
  if [ "$hook_begin_count" -eq 0 ] && [ "$hook_end_count" -eq 0 ]; then
    printf '%s\n' missing
  elif [ "$hook_begin_count" -eq 1 ] && [ "$hook_end_count" -eq 1 ]; then
    actual_block=$(awk -v begin="$begin_marker" -v end="$end_marker" '
      $0 == begin { capture=1 }
      capture { print }
      $0 == end && capture { exit }
    ' "$services_start" 2>/dev/null || true)
    expected_block=$(write_canonical_block)
    if sed -n '1p' "$services_start" | grep -q '^#!'; then expected_begin_line=2; else expected_begin_line=1; fi
    actual_begin_line=$(awk -v begin="$begin_marker" '$0 == begin { print NR; exit }' "$services_start" 2>/dev/null || true)
    if [ "$actual_block" = "$expected_block" ] && [ "$actual_begin_line" = "$expected_begin_line" ]; then
      printf '%s\n' ready
    else
      printf '%s\n' drifted
    fi
  else
    printf '%s\n' drifted
  fi
}

write_canonical_block() {
  printf '%s\n' "$begin_marker"
  printf 'if [ -x "%s" ]; then\n' "$reconciler"
  if [ -n "$root" ]; then
    printf '  HOME_EDGE_RECONCILE_ROOT="%s" "%s" --boot\n' "$root" "$reconciler"
  else
    printf '  "%s" --boot\n' "$reconciler_rel"
  fi
  printf 'fi\n'
  printf '%s\n' "$end_marker"
}

registration_state() {
  if ! command -v cru >/dev/null 2>&1; then
    printf '%s\n' unavailable
    return 0
  fi
  cron_list=$(cru l 2>/dev/null || true)
  matches=$(printf '%s\n' "$cron_list" | grep -F "#$job_name#" || true)
  count=$(printf '%s\n' "$matches" | grep -c . || true)
  if [ "$count" -eq 0 ]; then
    printf '%s\n' missing
  elif [ "$count" -ne 1 ]; then
    printf '%s\n' duplicate
  elif [ "$matches" = "$schedule sh $wrapper_rel #$job_name#" ]; then
    printf '%s\n' ready
  else
    printf '%s\n' drifted
  fi
}

emit_status() {
  registration=$(registration_state)
  hook=$(boot_hook_state)
  if [ "$dry_run" = "0" ]; then mode=live; else mode=dry_run; fi
  printf 'self_heal_registration_state=%s\n' "$registration"
  printf 'self_heal_boot_hook_state=%s\n' "$hook"
  printf 'self_heal_policy_mode=%s\n' "$mode"
}

install_boot_hook() {
  [ -s "$reconciler" ] || die "missing installed reconciler: $reconciler"
  mkdir -p "$(dirname "$services_start")" || die "cannot prepare services-start directory"
  if [ ! -e "$services_start" ]; then
    printf '#!/bin/sh\n' >"$services_start" || die "cannot create services-start"
  fi
  [ -f "$services_start" ] && [ ! -L "$services_start" ] || die "services-start must be a regular file"
  original_mode=$(stat -c '%a' "$services_start" 2>/dev/null || stat -f '%Lp' "$services_start" 2>/dev/null || true)
  case "$original_mode" in
    [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
    *) original_mode=700 ;;
  esac

  hook_marker_counts
  [ "$hook_begin_count" -eq "$hook_end_count" ] && [ "$hook_begin_count" -le 1 ] ||
    die "unbalanced managed lifecycle markers in services-start"
  if [ "$hook_begin_count" -eq 1 ] && ! awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin { if (state != 0) invalid=1; state=1 }
    $0 == end { if (state != 1) invalid=1; state=2 }
    END { exit (invalid || state != 2) }
  ' "$services_start"; then
    die "invalid managed lifecycle marker order in services-start"
  fi

  tmp_hook="${services_start}.tmp.$$"
  if ! cp -p "$services_start" "$tmp_hook" 2>/dev/null; then
    : >"$tmp_hook" || die "cannot stage services-start"
    chmod 700 "$tmp_hook" || die "cannot secure staged services-start"
  fi
  awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin { managed=1; next }
    $0 == end { managed=0; next }
    !managed { print }
  ' "$services_start" >"${tmp_hook}.content" || die "cannot stage services-start"
  if sed -n '1p' "${tmp_hook}.content" | grep -q '^#!'; then
    {
      sed -n '1p' "${tmp_hook}.content"
      write_canonical_block
      sed '1d' "${tmp_hook}.content"
    } >"${tmp_hook}.assembled" || die "cannot assemble services-start"
  else
    {
      write_canonical_block
      cat "${tmp_hook}.content"
    } >"${tmp_hook}.assembled" || die "cannot assemble services-start"
  fi
  cat "${tmp_hook}.assembled" >"$tmp_hook" || die "cannot stage services-start"
  rm -f "${tmp_hook}.content" "${tmp_hook}.assembled"
  chmod "$original_mode" "$tmp_hook" 2>/dev/null || chmod 700 "$tmp_hook" || die "cannot restore services-start mode"
  chmod u+x "$tmp_hook" || die "cannot make services-start owner-executable"
  mv "$tmp_hook" "$services_start" || die "cannot activate services-start"
  tmp_hook=""
}

reconcile_cron() {
  command -v cru >/dev/null 2>&1 || die "cru is required for self-heal registration"
  [ -s "$wrapper" ] || die "missing cron wrapper: $wrapper"
  expected_line="$schedule sh $wrapper_rel #$job_name#"
  prior_list=$(cru l 2>/dev/null || true)
  prior_matches=$(printf '%s\n' "$prior_list" | grep -F "#$job_name#" || true)
  prior_count=$(printf '%s\n' "$prior_matches" | grep -c . || true)
  prior_healthy=0
  if [ "$prior_count" -eq 1 ] && [ "$prior_matches" = "$expected_line" ]; then
    prior_healthy=1
  fi

  restore_prior_registration() {
    cru d "$job_name" >/dev/null 2>&1 || true
    [ "$prior_healthy" = "1" ] || return 1
    cru a "$job_name" "$schedule sh $wrapper_rel" >/dev/null 2>&1 || return 1
    restored=$(cru l 2>/dev/null || true)
    [ "$(printf '%s\n' "$restored" | grep -Fxc "$expected_line" 2>/dev/null || true)" -eq 1 ]
  }

  cru d "$job_name" >/dev/null 2>&1 || true
  if ! cru a "$job_name" "$schedule sh $wrapper_rel"; then
    restore_prior_registration || die "cannot register self-heal cron; no single healthy prior registration could be restored"
    die "cannot register self-heal cron; exact prior registration restored"
  fi
  if [ "$(registration_state)" != "ready" ]; then
    restore_prior_registration || die "self-heal cron verification failed; no single healthy prior registration could be restored"
    die "self-heal cron verification failed; exact prior registration restored"
  fi
}

load_policy
case "${1:---status}" in
  --install)
    acquire_lock
    install_boot_hook
    reconcile_cron
    emit_status
    ;;
  --reconcile|--boot)
    acquire_lock
    reconcile_cron
    emit_status
    ;;
  --status)
    emit_status
    ;;
  --help|-h)
    echo "usage: sh reconcile-self-heal-registration.sh [--install|--reconcile|--boot|--status]"
    ;;
  *)
    die "unsupported action: $1"
    ;;
esac
