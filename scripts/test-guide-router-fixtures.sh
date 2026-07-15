#!/bin/sh
# Offline behavior tests for guide-router.sh next_action_code and JSON output.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

fail() {
  echo "guide_router_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

run_case() {
  name="$1"
  fixture="$2"
  expected="$3"

  output=$(
    GUIDE_ROUTER_FIXTURE_AUDIT_OUTPUT="$fixture" \
    sh "$repo/scripts/guide-router.sh" --json user@192.168.50.1
  )

  printf '%s\n' "$output" | grep -q '"guide_state": "ready"' || fail "$name missing ready guide_state"
  printf '%s\n' "$output" | grep -q "\"next_action_code\": \"$expected\"" || fail "$name expected next_action_code=$expected"
  printf '%s\n' "$output" | grep -q '"next_action_command":' || fail "$name missing next_action_command"
}

run_case missing_prereqs 'device_state=ssh_reachable
firmware_state=official_merlin
admin_state=ssh_reachable
baseline_state=reviewed
proxy_state=absent
subscription_state=missing
automation_state=audit_only
risk_count=0
review_count=0
monitor_count=0' enable_router_prereqs

run_case deploy_plan 'device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed
proxy_state=absent
subscription_state=missing
automation_state=apply_ready
risk_count=0
review_count=0
monitor_count=0' deploy_plan

run_case enable_live_self_heal 'device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed_with_monitoring
proxy_state=verified
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1' enable_live_self_heal

run_case repair_self_heal_registration 'device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed_with_monitoring
proxy_state=verified
self_heal_registration_state=missing
self_heal_boot_hook_state=missing
subscription_state=cache_ready
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1' repair_self_heal_registration

run_case deploy_pre_lifecycle_installation 'device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed_with_monitoring
proxy_state=verified
lifecycle_reconciler_state=absent
self_heal_registration_state=missing
self_heal_boot_hook_state=missing
subscription_state=cache_ready
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1' deploy_plan

run_case configure_controller_auth 'device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
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
monitor_count=1' configure_controller_auth

run_case inspect_or_start_proxy_runtime 'device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed_with_monitoring
proxy_state=policy_deployed
runtime_state=controller_unreachable
controller_state=unreachable
controller_auth_state=unknown
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
subscription_consumption_state=cache_only_unverified
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1' inspect_or_start_proxy_runtime

run_case monitor_live_managed 'device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed_with_monitoring
proxy_state=verified
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
automation_state=live_managed
risk_count=0
review_count=0
monitor_count=1' monitor_live_managed

echo "guide_router_fixture_tests=ok"
