#!/bin/sh
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_base=${TMPDIR:-/tmp}
[ "$tmp_base" = "/" ] || tmp_base=${tmp_base%/}
base="$tmp_base/home-edge-run-bootstrap-fixtures-sh-$$"
case "$base" in *//*) echo "run_bootstrap_fixture_tests=failed" >&2; echo "temporary fixture root was not normalized: $base" >&2; exit 1 ;; esac
rm -rf "$base"
mkdir -p "$base"

fail() {
  echo "run_bootstrap_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

run_case() {
  name=$1
  guide_json=$2
  closeout_output=$3
  expected_state=$4
  expected_action=${5:-}
  forbidden_logs=${6:-}
  session="$base/$name"
  if [ -n "$closeout_output" ]; then
    output=$(BOOTSTRAP_TEST_MODE=1 BOOTSTRAP_FIXTURE_GUIDE_JSON="$guide_json" BOOTSTRAP_FIXTURE_CLOSEOUT_OUTPUT="$closeout_output" sh "$repo/scripts/run-bootstrap.sh" --no-pause --accept-client-runtime --client-confirmed --session-dir "$session" user@192.168.50.1)
  else
    output=$(BOOTSTRAP_TEST_MODE=1 BOOTSTRAP_FIXTURE_GUIDE_JSON="$guide_json" sh "$repo/scripts/run-bootstrap.sh" --no-pause --accept-client-runtime --client-confirmed --session-dir "$session" user@192.168.50.1)
  fi
  printf '%s\n' "$output" | grep -q "bootstrap_state=$expected_state" || fail "$name expected bootstrap_state=$expected_state"
  if [ -n "$expected_action" ]; then
    printf '%s\n' "$output" | grep -q "next_action_code=$expected_action" || fail "$name expected next_action_code=$expected_action"
  fi
  [ -f "$session/logs/bootstrap.log" ] || fail "$name missing bootstrap log"
  [ -f "$session/state.env" ] || fail "$name missing state.env"
  grep -Fq "known_hosts_file=$session/known_hosts" "$session/state.env" || fail "$name state does not retain the session known_hosts path"
  [ ! -e "$session/state.env.tmp" ] || fail "$name left an atomic state temp file"
  [ ! -d "$session/.bootstrap.lock" ] || fail "$name left a bootstrap lock"
  { [ "$expected_state" != pass ] && [ "$expected_state" != accepted_boundary ]; } || [ ! -d "$session/scratch" ] || fail "$name did not clean scratch after terminal result"
  for forbidden_log in $forbidden_logs; do
    [ ! -f "$session/logs/$forbidden_log" ] || fail "$name created forbidden log: $forbidden_log"
  done
}

run_case waiting_prereqs '{"guide_state":"ready","next_action_code":"enable_router_prereqs","next_action_command":"guide"}' '' waiting_manual enable_router_prereqs
run_case deploy_requires_apply '{"guide_state":"ready","next_action_code":"deploy_plan","next_action_command":"deploy"}' '' waiting_manual deploy_plan 'deploy-plan.log deploy-apply.log'
run_case repair_registration '{"guide_state":"ready","next_action_code":"repair_self_heal_registration","next_action_command":"repair"}' '' waiting_manual repair_self_heal_registration
run_case pass_closeout '{"guide_state":"ready","next_action_code":"monitor_live_managed","next_action_command":"status"}' 'repository_gate=pass
router_gate=pass
runtime_gate=pass
route_gate=pass
subscription_gate=pass
client_gate=pass
installation_closeout_state=pass
next_action=none' pass
run_case accepted_boundary_closeout '{"guide_state":"ready","next_action_code":"monitor_live_managed","next_action_command":"status"}' 'repository_gate=pass
router_gate=pass
runtime_gate=pass
route_gate=pass
subscription_gate=accepted_manual_boundary
dashboard_gate=not_applicable
client_gate=pass
installation_closeout_state=accepted_boundary
next_action=none' accepted_boundary

busy_session="$base/busy_lock"
mkdir -p "$busy_session/.bootstrap.lock"
printf 'pid=%s\nstarted_at=test\n' "$$" >"$busy_session/.bootstrap.lock/owner"
set +e
busy_output=$(BOOTSTRAP_TEST_MODE=1 BOOTSTRAP_FIXTURE_GUIDE_JSON='{"guide_state":"ready","next_action_code":"enable_router_prereqs","next_action_command":"guide"}' sh "$repo/scripts/run-bootstrap.sh" --no-pause --session-dir "$busy_session" user@192.168.50.1 2>&1)
busy_status=$?
set -e
[ "$busy_status" -eq 75 ] || fail "active bootstrap lock should exit 75, got $busy_status"
printf '%s\n' "$busy_output" | grep -q 'bootstrap_state=busy' || fail "active bootstrap lock did not report busy"
rm -rf "$busy_session"

unowned_session="$base/unowned_scratch"
mkdir -p "$unowned_session/scratch"
printf 'preserve\n' >"$unowned_session/scratch/user-file"
set +e
unowned_output=$(BOOTSTRAP_TEST_MODE=1 BOOTSTRAP_FIXTURE_GUIDE_JSON='{"guide_state":"ready","next_action_code":"enable_router_prereqs","next_action_command":"guide"}' sh "$repo/scripts/run-bootstrap.sh" --no-pause --session-dir "$unowned_session" user@192.168.50.1 2>&1)
unowned_status=$?
set -e
[ "$unowned_status" -ne 0 ] || fail "unowned scratch directory should be rejected"
printf '%s\n' "$unowned_output" | grep -q 'unowned scratch' || fail "unowned scratch rejection message missing"
[ -f "$unowned_session/scratch/user-file" ] || fail "unowned scratch content was removed"

set +e
root_output=$(BOOTSTRAP_TEST_MODE=1 BOOTSTRAP_FIXTURE_GUIDE_JSON='{"guide_state":"ready","next_action_code":"enable_router_prereqs","next_action_command":"guide"}' sh "$repo/scripts/run-bootstrap.sh" --no-pause --session-dir / user@192.168.50.1 2>&1)
root_status=$?
set -e
[ "$root_status" -ne 0 ] || fail "filesystem-root session directory should be rejected"
printf '%s\n' "$root_output" | grep -q 'unsafe bootstrap session directory' || fail "unsafe root session message missing"

stale_session="$base/stale_lock"
mkdir -p "$stale_session/.bootstrap.lock"
printf 'pid=999999\nstarted_at=test\n' >"$stale_session/.bootstrap.lock/owner"
stale_output=$(BOOTSTRAP_TEST_MODE=1 BOOTSTRAP_FIXTURE_GUIDE_JSON='{"guide_state":"ready","next_action_code":"enable_router_prereqs","next_action_command":"guide"}' sh "$repo/scripts/run-bootstrap.sh" --no-pause --session-dir "$stale_session" user@192.168.50.1)
printf '%s\n' "$stale_output" | grep -q 'bootstrap_state=waiting_manual' || fail "stale bootstrap lock was not recovered"
[ ! -d "$stale_session/.bootstrap.lock" ] || fail "recovered stale bootstrap lock was not released"

rm -rf "$base"
echo "run_bootstrap_fixture_tests=ok"
