#!/bin/sh
# Resumable host-side bootstrap loop for macOS/Linux/Git Bash.
set -u

router=${ROUTER:-}
session_dir=""
max_loops=20
apply_deploy=0
enable_live_self_heal=0
accept_runtime_imported_subscription=0
accept_client_runtime=0
dashboard_confirmed=0
client_confirmed=0
run_client_check=0
no_pause=0

while [ $# -gt 0 ]; do
  case "$1" in
    --apply-deploy) apply_deploy=1 ;;
    --enable-live-self-heal) enable_live_self_heal=1 ;;
    --accept-runtime-imported-subscription) accept_runtime_imported_subscription=1 ;;
    --accept-client-runtime) accept_client_runtime=1 ;;
    --dashboard-confirmed) dashboard_confirmed=1 ;;
    --client-confirmed) client_confirmed=1 ;;
    --run-client-check) run_client_check=1 ;;
    --no-pause) no_pause=1 ;;
    --session-dir)
      shift
      [ $# -gt 0 ] || { echo "--session-dir requires a path" >&2; exit 2; }
      session_dir=$1
      ;;
    --max-loops)
      shift
      [ $# -gt 0 ] || { echo "--max-loops requires a number" >&2; exit 2; }
      max_loops=$1
      ;;
    --help|-h)
      echo "usage: sh scripts/run-bootstrap.sh [options] <ssh-user>@<router-ip>" >&2
      exit 2
      ;;
    *)
      if [ -z "$router" ]; then router=$1; else echo "unexpected argument: $1" >&2; exit 2; fi
      ;;
  esac
  shift
done

[ -n "$router" ] || { echo "Router is required. Pass <ssh-user>@<router-ip> or set ROUTER." >&2; exit 2; }
case "$max_loops" in ''|*[!0-9]*) echo "--max-loops must be numeric" >&2; exit 2 ;; esac

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
router_id=$(printf '%s' "$router" | sed 's/[^A-Za-z0-9_.-]/_/g')
[ -n "$session_dir" ] || session_dir="$repo/logs/bootstrap/$router_id"
mkdir -p "$session_dir" || { echo "cannot create bootstrap session directory: $session_dir" >&2; exit 2; }
session_dir=$(CDPATH= cd "$session_dir" && pwd)
case "$session_dir" in
  /|/[A-Za-z]) echo "unsafe bootstrap session directory: $session_dir" >&2; exit 2 ;;
esac
log_dir="$session_dir/logs"
scratch_dir="$session_dir/scratch"
scratch_marker="$scratch_dir/.home-edge-bootstrap-scratch"
state_path="$session_dir/state.env"
main_log="$log_dir/bootstrap.log"
known_hosts_file="$session_dir/known_hosts"
lock_dir="$session_dir/.bootstrap.lock"
log_max_bytes="${BOOTSTRAP_LOG_MAX_BYTES:-2097152}"
guide_audit_log="$log_dir/router-guide-audit.log"
router_status_log="$log_dir/router-status.log"
mkdir -p "$log_dir"
if [ -e "$scratch_dir" ]; then
  [ -d "$scratch_dir" ] || { echo "bootstrap scratch path is not a directory: $scratch_dir" >&2; exit 2; }
  [ -f "$scratch_marker" ] || {
    echo "refusing to reuse unowned scratch directory: $scratch_dir" >&2
    exit 2
  }
fi
mkdir -p "$scratch_dir"
: >"$scratch_marker"
if [ -f "$main_log" ]; then
  main_log_bytes=$(wc -c <"$main_log" | tr -d " ")
  case "$main_log_bytes" in ''|*[!0-9]*) main_log_bytes=0 ;; esac
  if [ "$main_log_bytes" -gt "$log_max_bytes" ]; then
    mv -f "$main_log" "$main_log.1"
  fi
fi


now_iso() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log_msg() {
  level=$1
  shift
  line="$(now_iso) [$level] $*"
  printf '%s\n' "$line" | tee -a "$main_log"
}
write_state() {
  state=$1
  phase=$2
  code=${3:-}
  command=${4:-}
  state_tmp="$state_path.tmp"
  cat >"$state_tmp" <<EOF
bootstrap_state=$state
phase=$phase
router=$router
session_dir=$session_dir
log_dir=$log_dir
next_action_code=$code
next_action_command=$command
known_hosts_file=$known_hosts_file
updated_at=$(now_iso)
EOF
  mv -f "$state_tmp" "$state_path"
}
json_get() {
  key=$1
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}
kv_get() {
  key=$1
  awk -F= -v key="$key" '$1 == key { value=$0; sub("^[^=]*=", "", value); print value; exit }'
}
run_step() {
  name=$1
  shift
  step_log="$log_dir/$name.log"
  log_msg INFO "step_start=$name log=$step_log"
  if [ "${BOOTSTRAP_TEST_MODE:-0}" = "1" ]; then
    printf '%s\n' "BOOTSTRAP_TEST_MODE skipped step: $name" >"$step_log"
    log_msg INFO "step_skipped_test_mode=$name"
    return 0
  fi
  if "$@" >"$step_log" 2>&1; then
    log_msg INFO "step_end=$name exit_code=0"
    return 0
  fi
  status=$?
  log_msg ERROR "step_failed=$name exit_code=$status"
  write_state failed "$name" "step_failed" "inspect:$step_log"
  return "$status"
}
invoke_guide() {
  if [ -n "${BOOTSTRAP_FIXTURE_GUIDE_JSON:-}" ]; then
    printf '%s\n' "$BOOTSTRAP_FIXTURE_GUIDE_JSON"
    return 0
  fi
  GUIDE_ROUTER_JSON=1 LOG_PATH="$guide_audit_log" KNOWN_HOSTS_FILE="$known_hosts_file" sh "$repo/scripts/guide-router.sh" --json "$router"
}
invoke_closeout() {
  if [ -n "${BOOTSTRAP_FIXTURE_CLOSEOUT_OUTPUT:-}" ]; then
    printf '%s\n' "$BOOTSTRAP_FIXTURE_CLOSEOUT_OUTPUT"
    return "${BOOTSTRAP_FIXTURE_CLOSEOUT_EXIT:-0}"
  fi
  args=""
  [ "$accept_runtime_imported_subscription" -eq 1 ] && args="$args --accept-runtime-imported-subscription"
  [ "$accept_client_runtime" -eq 1 ] && args="$args --accept-client-runtime"
  [ "$dashboard_confirmed" -eq 1 ] && args="$args --dashboard-confirmed"
  [ "$client_confirmed" -eq 1 ] && args="$args --client-confirmed"
  [ "$run_client_check" -eq 1 ] && args="$args --run-client-check"
  # shellcheck disable=SC2086
  sh "$repo/scripts/check-installation-closeout.sh" "$router" $args
}
wait_or_return() {
  code=$1
  command=$2
  message=$3
  write_state waiting_manual manual_intervention "$code" "$command"
  printf '\nbootstrap_state=waiting_manual\nnext_action_code=%s\nnext_action_command=%s\nsession_dir=%s\nlog_path=%s\n%s\n' "$code" "$command" "$session_dir" "$main_log" "$message"
  log_msg WAIT "next_action_code=$code command=$command"
  if [ "$no_pause" -eq 1 ]; then return 1; fi
  printf 'Complete the manual step, then press Enter to re-check: '
  # shellcheck disable=SC2034
  read ans
  return 0
}
prerequisite_help() {
  reason=$1
  evidence_file=${2:-}
  write_state waiting_prerequisite preflight "$reason" manual_prerequisite_setup
  printf '\nbootstrap_state=waiting_prerequisite\nnext_action_code=%s\nsession_dir=%s\nlog_path=%s\n' "$reason" "$session_dir" "$main_log"
  [ -n "$evidence_file" ] && [ -f "$evidence_file" ] && cat "$evidence_file"
  cat <<'EOF'

Manual prerequisite setup:
- Windows: enable/install OpenSSH Client; ensure tar.exe is available; rerun from Windows PowerShell 5.1 or newer. Optional: install Git for easier checkout management.
- macOS: run xcode-select --install if ssh/tar/gzip/base64/sed/awk/grep/date/mktemp are missing; Homebrew is optional.
- Linux: install openssh-client, tar, gzip, coreutils, sed, awk, grep, and ca-certificates with your distribution package manager.
- Router: enable LAN SSH and JFFS custom scripts/configs in the ASUS/Asuswrt-Merlin Web GUI; confirm the LAN IP and SSH user.
EOF
  log_msg WAIT "prerequisite_block=$reason"
}
acquire_lock() {
  if mkdir "$lock_dir" 2>/dev/null; then
    printf 'pid=%s\nstarted_at=%s\n' "$$" "$(now_iso)" >"$lock_dir/owner"
    return 0
  fi

  owner_pid=$(sed -n 's/^pid=//p' "$lock_dir/owner" 2>/dev/null | head -n 1)
  if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
    echo "bootstrap_state=busy" >&2
    echo "lock_owner_pid=$owner_pid" >&2
    echo "session_dir=$session_dir" >&2
    return 75
  fi

  rm -rf "$lock_dir"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    echo "bootstrap_state=busy" >&2
    echo "session_dir=$session_dir" >&2
    return 75
  fi
  printf 'pid=%s\nstarted_at=%s\nrecovered_stale_lock=1\n' "$$" "$(now_iso)" >"$lock_dir/owner"
}
release_lock() {
  [ ! -d "$lock_dir" ] || rm -rf "$lock_dir"
}
handle_interrupt() {
  write_state interrupted interrupted resume "sh scripts/run-bootstrap.sh --session-dir \"$session_dir\" \"$router\""
  log_msg WARN "bootstrap_interrupted resume_session=$session_dir"
  exit 130
}

if ! acquire_lock; then exit 75; fi
trap 'release_lock' EXIT
trap 'handle_interrupt' HUP INT TERM


preflight() {
  if [ "${BOOTSTRAP_TEST_MODE:-0}" = "1" ]; then
    log_msg INFO preflight_skipped_test_mode=1
    return 0
  fi
  if ! run_step preflight-no-wall sh "$repo/scripts/check-no-wall-readiness.sh"; then
    prerequisite_help missing_local_tools "$log_dir/preflight-no-wall.log"
    return 1
  fi
  if ! run_step preflight-host-ssh env KNOWN_HOSTS_FILE="$known_hosts_file" sh "$repo/scripts/check-host-ssh.sh" "$router"; then
    prerequisite_help host_ssh_check_failed "$log_dir/preflight-host-ssh.log"
    return 1
  fi
  host_state=$(cat "$log_dir/preflight-host-ssh.log" | kv_get host_ssh_check_state)
  if [ "$host_state" != ready ]; then
    hint=$(cat "$log_dir/preflight-host-ssh.log" | kv_get ssh_failure_hint)
    [ -n "$hint" ] || hint=$host_state
    prerequisite_help "$hint" "$log_dir/preflight-host-ssh.log"
    return 1
  fi
  return 0
}
cleanup_scratch() {
  if [ -f "$scratch_marker" ]; then
    rm -rf "$scratch_dir"
    log_msg INFO cleanup=scratch_removed
    return 0
  fi
  log_msg WARN "cleanup=skipped_unowned_scratch path=$scratch_dir"
  return 1
}

write_state running start
log_msg INFO "bootstrap_start router=$router session_dir=$session_dir"
preflight || exit 0

loop=1
while [ "$loop" -le "$max_loops" ]; do
  write_state running guide
  log_msg INFO "loop=$loop"
  guide_output=$(invoke_guide) || {
    printf '%s\n' "$guide_output" >"$log_dir/guide-router.failed.log"
    write_state failed guide
    exit 1
  }
  code=$(printf '%s\n' "$guide_output" | json_get next_action_code)
  command=$(printf '%s\n' "$guide_output" | json_get next_action_command)
  [ -n "$code" ] || code=inspect_audit_log
  [ -n "$command" ] || command="sh scripts/guide-router.sh \"$router\""
  log_msg INFO "guide_next_action=$code"

  case "$code" in
    enable_router_prereqs)
      wait_or_return "$code" "$command" "Enable LAN SSH and JFFS custom scripts/configs in the router Web UI, then continue." || exit 0
      ;;
    resolve_action_findings)
      wait_or_return "$code" "$command" "Resolve ACTION findings from the audit, then continue." || exit 0
      ;;
    review_baseline_findings)
      wait_or_return "$code" "$command" "Review and accept or correct REVIEW findings, then continue." || exit 0
      ;;
    deploy_plan)
      if [ "$apply_deploy" -eq 1 ]; then
        run_step deploy-apply env APPLY=1 KNOWN_HOSTS_FILE="$known_hosts_file" sh "$repo/scripts/deploy-merlin.sh" "$router" || exit 1
      else
        log_msg INFO "deploy_ready apply_required=1"
        wait_or_return "$code" "sh scripts/run-bootstrap.sh --apply-deploy \"$router\"" "Deployment is ready. Rerun with --apply-deploy after reviewing the guide output, or deploy manually and continue." || exit 0
      fi
      ;;
    store_or_import_subscription)
      wait_or_return "$code" "$command" "Store the provider subscription with store-subscription, or import/start it in ShellCrash, then continue." || exit 0
      ;;
    store_subscription_for_managed_switching)
      wait_or_return "$code" "$command" "The live route works, but project-managed provider switching needs the subscription stored on the router." || exit 0
      ;;
    inspect_self_heal_dry_run)
      run_step router-status env LOG_PATH="$router_status_log" KNOWN_HOSTS_FILE="$known_hosts_file" sh "$repo/scripts/check-router-status.sh" "$router" || true
      wait_or_return "$code" "sh scripts/check-router-status.sh \"$router\"" "Inspect the DRY-RUN self-heal log. Continue after the route is healthy." || exit 0
      ;;
    repair_self_heal_registration)
      wait_or_return "$code" "$command" "Restore the project-owned boot hook and self-heal scheduler, then continue." || exit 0
      ;;
    enable_live_self_heal)
      if [ "$enable_live_self_heal" -eq 1 ]; then
        run_step enable-live-self-heal env KNOWN_HOSTS_FILE="$known_hosts_file" sh "$repo/scripts/enable-live-self-heal.sh" "$router" || exit 1
      else
        wait_or_return "$code" "sh scripts/run-bootstrap.sh --enable-live-self-heal \"$router\"" "The route is verified in DRY-RUN. Rerun with --enable-live-self-heal when you are ready for real automatic switching." || exit 0
      fi
      ;;
    monitor_live_managed)
      closeout_log="$log_dir/installation-closeout.log"
      if invoke_closeout >"$closeout_log" 2>&1; then closeout_status=0; else closeout_status=$?; fi
      closeout_state=$(cat "$closeout_log" | kv_get installation_closeout_state)
      next=$(cat "$closeout_log" | kv_get next_action)
      if [ "$closeout_state" = pass ]; then
        cleanup_scratch
        write_state pass complete none none
        printf '\nbootstrap_state=pass\ninstallation_closeout_state=pass\nsession_dir=%s\nlog_path=%s\n' "$session_dir" "$main_log"
        log_msg INFO bootstrap_complete
        exit 0
      fi
      if [ "$closeout_state" = accepted_boundary ]; then
        cleanup_scratch
        write_state accepted_boundary accepted_boundary none none
        printf '\nbootstrap_state=accepted_boundary\ninstallation_closeout_state=accepted_boundary\nsession_dir=%s\nlog_path=%s\n' "$session_dir" "$main_log"
        log_msg INFO bootstrap_accepted_boundary
        exit 0
      fi
      [ -n "$next" ] || next="Inspect installation closeout log, then continue."
      wait_or_return "installation_closeout_${closeout_state:-unknown}" "$command" "$next" || exit 0
      ;;
    *)
      wait_or_return "$code" "$command" "State is incomplete or unknown. Inspect the session logs, then continue." || exit 0
      ;;
  esac
  loop=$((loop + 1))
done

write_state failed max_loops_exceeded
log_msg ERROR "max_loops_exceeded=$max_loops"
echo "Bootstrap did not converge within $max_loops loops. See $main_log" >&2
exit 1
