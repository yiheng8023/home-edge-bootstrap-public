#!/bin/sh
# Offline client-gate tests for check-installation-closeout.sh.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-closeout-client-fixture.XXXXXX")
fixture_scripts="$fixture_root/scripts"
mkdir -p "$fixture_scripts"
trap 'rm -rf "$fixture_root"' EXIT HUP INT TERM

fail() {
  echo "installation_closeout_client_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

state_from() {
  key="$1"
  input="$2"
  printf '%s\n' "$input" | awk -F= -v key="$key" '$1 == key { value=$0; sub("^[^=]*=", "", value); print value; exit }'
}

cp "$repo/scripts/check-installation-closeout.sh" "$fixture_scripts/check-installation-closeout.sh"

cat > "$fixture_scripts/verify-closeout.sh" <<'EOF'
#!/bin/sh
echo 'closeout_state=ready'
EOF

cat > "$fixture_scripts/guide-router.sh" <<'EOF'
#!/bin/sh
cat <<STATE
device_state=ssh_reachable
admin_state=jffs_scripts_ready
baseline_state=reviewed
proxy_state=verified
runtime_state=running
runtime_process_state=${INSTALLATION_CLOSEOUT_RUNTIME_PROCESS:-running}
controller_state=reachable
controller_auth_state=authenticated
controller_observation_state=ready
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
subscription_consumption_state=${INSTALLATION_CLOSEOUT_SUB_CONSUMPTION:-runtime_profile_matches_cache}
dashboard_config_state=${INSTALLATION_CLOSEOUT_DASHBOARD_CONFIG:-not_configured}
dashboard_reachability_state=${INSTALLATION_CLOSEOUT_DASHBOARD_REACHABILITY:-unverified}
automation_state=live_managed
risk_count=0
review_count=0
monitor_count=0
STATE
EOF

cat > "$fixture_scripts/check-router-status.sh" <<'EOF'
#!/bin/sh
echo 'controller_observation_state=ready'
echo 'self-heal: OK current=Fixture Route reaches probe target; no change'
echo "route_evidence_probe_id=${INSTALLATION_CLOSEOUT_ROUTE_PROBE_ID:-fixture-1}"
echo "route_evidence_identity=Fixture Route"
echo "route_evidence_classification=reachable"
echo "route_evidence_verification_state=${INSTALLATION_CLOSEOUT_ROUTE_STATE:-pass}"
EOF

cat > "$fixture_scripts/check-client-topology.sh" <<'EOF'
#!/bin/sh
runtime=${INSTALLATION_CLOSEOUT_CLIENT_RUNTIME:-unknown}
case "$runtime" in
  0) mode=router_primary; risk=low ;;
  1) mode=hybrid; risk=medium ;;
  *) mode=unknown; risk=unknown ;;
esac
echo "client_topology_mode=$mode"
echo "client_runtime_present=$runtime"
echo 'gateway_matches_router=yes'
echo 'client_http_state=ok:204'
echo "client_conflict_risk=$risk"
EOF

chmod +x "$fixture_scripts"/*.sh

run_case() {
  name="$1"
  runtime="$2"
  expected_gate="$3"
  expected_closeout="$4"
  consumption="${5:-runtime_profile_matches_cache}"
  expected_subscription_gate="${6:-pass}"
  dashboard_config="${7:-not_configured}"
  dashboard_reachability="${8:-unverified}"
  extra_args="${9:-}"
  expected_dashboard_gate="${10:-not_applicable}"
  expected_dashboard_evidence="${11:-not_applicable}"

  closeout_exit=0
  # shellcheck disable=SC2086
  output=$(INSTALLATION_CLOSEOUT_CLIENT_RUNTIME="$runtime" INSTALLATION_CLOSEOUT_SUB_CONSUMPTION="$consumption" INSTALLATION_CLOSEOUT_DASHBOARD_CONFIG="$dashboard_config" INSTALLATION_CLOSEOUT_DASHBOARD_REACHABILITY="$dashboard_reachability" sh "$fixture_scripts/check-installation-closeout.sh" user@192.168.50.1 --run-client-check $extra_args) || closeout_exit=$?
  gate=$(state_from client_gate "$output")
  subscription_gate=$(state_from subscription_gate "$output")
  dashboard_gate=$(state_from dashboard_gate "$output")
  dashboard_evidence=$(state_from dashboard_evidence "$output")
  closeout=$(state_from installation_closeout_state "$output")
  next_action=$(state_from next_action "$output")
  [ "$gate" = "$expected_gate" ] || fail "$name expected client_gate=$expected_gate got=$gate"
  [ "$subscription_gate" = "$expected_subscription_gate" ] || fail "$name expected subscription_gate=$expected_subscription_gate got=$subscription_gate"
  [ "$dashboard_gate" = "$expected_dashboard_gate" ] || fail "$name expected dashboard_gate=$expected_dashboard_gate got=$dashboard_gate"
  [ "$dashboard_evidence" = "$expected_dashboard_evidence" ] || fail "$name expected dashboard_evidence=$expected_dashboard_evidence got=$dashboard_evidence"
  [ "$closeout" = "$expected_closeout" ] || fail "$name expected installation_closeout_state=$expected_closeout got=$closeout"
  if [ "$runtime" = "unknown" ]; then
    printf '%s\n' "$next_action" | grep -q 'read-only client topology check' || fail "$name expected an actionable read-only topology recheck, got=$next_action"
  fi
  if [ "$expected_closeout" = "pass" ] || [ "$expected_closeout" = "accepted_boundary" ]; then
    [ "$closeout_exit" -eq 0 ] || fail "$name expected exit=0 got=$closeout_exit"
  else
    [ "$closeout_exit" -ne 0 ] || fail "$name expected nonzero exit got=0"
  fi
}

stale_output=$(INSTALLATION_CLOSEOUT_CLIENT_RUNTIME=0 INSTALLATION_CLOSEOUT_ROUTE_PROBE_ID= INSTALLATION_CLOSEOUT_ROUTE_STATE=fail sh "$fixture_scripts/check-installation-closeout.sh" user@192.168.50.1 --run-client-check 2>&1 || true)
[ "$(state_from route_gate "$stale_output")" = "fail" ] || fail "historical self-heal log line satisfied route gate"

unknown_runtime_output=$(INSTALLATION_CLOSEOUT_CLIENT_RUNTIME=0 INSTALLATION_CLOSEOUT_RUNTIME_PROCESS=unknown sh "$fixture_scripts/check-installation-closeout.sh" user@192.168.50.1 --run-client-check 2>&1 || true)
[ "$(state_from runtime_gate "$unknown_runtime_output")" = "fail" ] || fail "unknown runtime process evidence satisfied strong runtime gate"
not_detected_runtime_output=$(INSTALLATION_CLOSEOUT_CLIENT_RUNTIME=0 INSTALLATION_CLOSEOUT_RUNTIME_PROCESS=not_detected sh "$fixture_scripts/check-installation-closeout.sh" user@192.168.50.1 --run-client-check 2>&1 || true)
[ "$(state_from runtime_gate "$not_detected_runtime_output")" = "fail" ] || fail "not-detected runtime process evidence satisfied strong runtime gate"

alias_output=$(INSTALLATION_CLOSEOUT_CLIENT_RUNTIME=0 INSTALLATION_CLOSEOUT_SUB_CONSUMPTION=cache_apply_path_alias sh "$fixture_scripts/check-installation-closeout.sh" user@192.168.50.1 --run-client-check 2>&1 || true)
[ "$(state_from subscription_gate "$alias_output")" = "consumption_unverified" ] || fail "cache/apply alias satisfied subscription gate"
file_match_output=$(INSTALLATION_CLOSEOUT_CLIENT_RUNTIME=0 INSTALLATION_CLOSEOUT_SUB_CONSUMPTION=profile_file_matches_cache sh "$fixture_scripts/check-installation-closeout.sh" user@192.168.50.1 --run-client-check 2>&1 || true)
[ "$(state_from subscription_gate "$file_match_output")" = "consumption_unverified" ] || fail "file equality satisfied strong subscription gate"

run_case router_primary 0 pass pass
run_case known_runtime 1 client_runtime_present partial
run_case unknown_runtime unknown client_runtime_unknown partial
run_case cache_not_consumed 0 pass partial cache_only_unverified consumption_unverified
run_case accepted_subscription_boundary 0 pass accepted_boundary cache_only_unverified accepted_manual_boundary not_configured unverified '--accept-runtime-imported-subscription'
run_case configured_dashboard_unverified 0 pass partial runtime_profile_matches_cache pass configured unverified '' reachability_unverified unverified
run_case confirmed_dashboard 0 pass pass runtime_profile_matches_cache pass configured unverified '--dashboard-confirmed' pass user_confirmed

echo "installation_closeout_client_fixture_tests=ok"
