#!/bin/sh
# Offline behavior tests for check-edge-health.sh JSON output.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

fail() {
  echo "edge_health_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

guide_fixture='device_state=ssh_reachable
baseline_state=reviewed_with_monitoring
proxy_state=verified
runtime_state=running
controller_state=reachable
controller_auth_state=authenticated
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
subscription_consumption_state=runtime_profile_matches_cache
automation_state=live_managed
risk_count=0
review_count=0
monitor_count=1'

client_fixture='client_topology_mode=hybrid
client_runtime_present=1
client_conflict_risk=medium
gateway_matches_router=yes
client_http_state=ok:204'

output=$(
  EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT="$guide_fixture" \
  EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT="$client_fixture" \
  sh "$repo/scripts/check-edge-health.sh" --json user@192.168.50.1
)

printf '%s\n' "$output" | grep -q '"edge_health_state": "router_managed"' || fail "missing router_managed JSON state"
printf '%s\n' "$output" | grep -q '"proxy_state": "verified"' || fail "missing proxy_state JSON field"
printf '%s\n' "$output" | grep -q '"subscription_state": "cache_ready"' || fail "missing subscription_state JSON field"
printf '%s\n' "$output" | grep -q '"client_topology_mode": "hybrid"' || fail "missing client_topology_mode JSON field"
printf '%s\n' "$output" | grep -q '"client_conflict_risk": "medium"' || fail "missing client_conflict_risk JSON field"
printf '%s\n' "$output" | grep -q '"next_action": "none"' || fail "missing next_action JSON field"

unknown_client_fixture='client_topology_mode=unknown
client_runtime_present=unknown
client_conflict_risk=unknown
gateway_matches_router=yes
client_http_state=ok:204'

unknown_output=$(
  EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT="$guide_fixture" \
  EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT="$unknown_client_fixture" \
  sh "$repo/scripts/check-edge-health.sh" --json user@192.168.50.1
)

printf '%s\n' "$unknown_output" | grep -q '"client_topology_mode": "unknown"' || fail "unknown client_topology_mode did not pass through"
printf '%s\n' "$unknown_output" | grep -q '"client_runtime_present": "unknown"' || fail "unknown client_runtime_present did not pass through"
printf '%s\n' "$unknown_output" | grep -q '"client_conflict_risk": "unknown"' || fail "unknown client_conflict_risk did not pass through"

registration_output=$(
  EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT='device_state=ssh_reachable
baseline_state=reviewed_with_monitoring
proxy_state=verified
runtime_state=running
controller_state=reachable
controller_auth_state=authenticated
self_heal_registration_state=missing
self_heal_boot_hook_state=missing
subscription_state=cache_ready
subscription_consumption_state=cache_only_unverified
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1' \
  EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT="$client_fixture" \
  sh "$repo/scripts/check-edge-health.sh" --json user@192.168.50.1
)
printf '%s\n' "$registration_output" | grep -q '"edge_health_state": "lifecycle_registration_degraded"' || fail "missing lifecycle registration degradation state"

auth_output=$(
  EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT='device_state=ssh_reachable
baseline_state=reviewed_with_monitoring
proxy_state=policy_deployed
runtime_state=authentication_blocked
controller_state=reachable
controller_auth_state=required_or_failed
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
subscription_consumption_state=cache_only_unverified
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1' \
  EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT="$client_fixture" \
  sh "$repo/scripts/check-edge-health.sh" --json user@192.168.50.1
)
printf '%s\n' "$auth_output" | grep -q '"edge_health_state": "controller_auth_blocked"' || fail "missing controller auth blocked state"

echo "edge_health_fixture_tests=ok"
