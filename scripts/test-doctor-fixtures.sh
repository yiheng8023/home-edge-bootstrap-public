#!/bin/sh
# Offline behavior tests for doctor.sh JSON output.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

fail() {
  echo "doctor_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

repository_fixture='closeout_state=ready'
no_wall_fixture='status=tools_ready
bundle_state=verified'
host_ssh_fixture='host_ssh_check_state=ready
router_ssh_state=ok
ssh_failure_hint=unknown'
edge_health_fixture='edge_health_state=router_managed
proxy_state=verified
subscription_state=cache_ready
automation_state=live_managed
client_topology_mode=hybrid
client_runtime_present=1
client_conflict_risk=medium
next_action=none'

output=$(
  DOCTOR_FIXTURE_REPOSITORY_OUTPUT="$repository_fixture" \
  DOCTOR_FIXTURE_NO_WALL_OUTPUT="$no_wall_fixture" \
  DOCTOR_FIXTURE_HOST_SSH_OUTPUT="$host_ssh_fixture" \
  DOCTOR_FIXTURE_EDGE_HEALTH_OUTPUT="$edge_health_fixture" \
  sh "$repo/scripts/doctor.sh" --json user@192.168.50.1
)

printf '%s\n' "$output" | grep -q '"doctor_state": "ready"' || fail "missing ready doctor state"
printf '%s\n' "$output" | grep -q '"repository_state": "ready"' || fail "missing repository state"
printf '%s\n' "$output" | grep -q '"working_directory_state": "' || fail "missing working directory state"
printf '%s\n' "$output" | grep -q '"local_tools_state": "tools_ready"' || fail "missing local tools state"
printf '%s\n' "$output" | grep -q '"host_ssh_check_state": "ready"' || fail "missing host SSH state"
printf '%s\n' "$output" | grep -q '"edge_health_state": "router_managed"' || fail "missing edge health state"
printf '%s\n' "$output" | grep -q '"client_topology_mode": "hybrid"' || fail "missing client topology"
printf '%s\n' "$output" | grep -q '"next_action": "none"' || fail "missing next action"

echo "doctor_fixture_tests=ok"
