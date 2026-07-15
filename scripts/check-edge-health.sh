#!/bin/sh
# Read-only daily health summary for the router-primary/client-fallback model.
set -u

router="${ROUTER:-}"
json=0
case "${EDGE_HEALTH_JSON:-0}" in
  1|true|TRUE|yes|YES) json=1 ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      json=1
      ;;
    --help|-h)
      echo "usage: sh scripts/check-edge-health.sh [--json] <ssh-user>@<router-ip>" >&2
      echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
      exit 2
      ;;
    *)
      if [ -z "$router" ]; then
        router="$1"
      else
        echo "unexpected argument: $1" >&2
        exit 2
      fi
      ;;
  esac
  shift
done

if [ -z "$router" ]; then
  echo "usage: sh scripts/check-edge-health.sh [--json] <ssh-user>@<router-ip>" >&2
  echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
  exit 2
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
log_path="${LOG_PATH:-/tmp/home-edge-health-audit.log}"

state_from() {
  key="$1"
  input="$2"
  printf '%s\n' "$input" | awk -F= -v key="$key" '$1 == key { value=$0; sub("^[^=]*=", "", value); print value; exit }'
}

or_unknown() {
  value="$1"
  [ -n "$value" ] && printf '%s\n' "$value" || printf unknown
}

guide_exit=0
if [ -n "${EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT+x}" ]; then
  guide_output=$EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT
  guide_exit=${EDGE_HEALTH_FIXTURE_GUIDE_EXIT:-0}
else
  guide_output=$(LOG_PATH="$log_path" sh "$script_dir/guide-router.sh" "$router" 2>&1) || guide_exit=$?
fi

client_exit=0
if [ -n "${EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT+x}" ]; then
  client_output=$EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT
  client_exit=${EDGE_HEALTH_FIXTURE_CLIENT_EXIT:-0}
else
  client_output=$(sh "$script_dir/check-client-topology.sh" "$router" 2>&1) || client_exit=$?
fi

device_state=$(state_from device_state "$guide_output")
baseline_state=$(state_from baseline_state "$guide_output")
proxy_state=$(state_from proxy_state "$guide_output")
runtime_state=$(state_from runtime_state "$guide_output")
controller_state=$(state_from controller_state "$guide_output")
controller_auth_state=$(state_from controller_auth_state "$guide_output")
self_heal_registration_state=$(state_from self_heal_registration_state "$guide_output")
self_heal_boot_hook_state=$(state_from self_heal_boot_hook_state "$guide_output")
subscription_state=$(state_from subscription_state "$guide_output")
subscription_consumption_state=$(state_from subscription_consumption_state "$guide_output")
automation_state=$(state_from automation_state "$guide_output")
risk_count=$(state_from risk_count "$guide_output")
review_count=$(state_from review_count "$guide_output")
monitor_count=$(state_from monitor_count "$guide_output")

client_topology_mode=$(state_from client_topology_mode "$client_output")
client_runtime_present=$(state_from client_runtime_present "$client_output")
client_conflict_risk=$(state_from client_conflict_risk "$client_output")
gateway_matches_router=$(state_from gateway_matches_router "$client_output")
client_http_state=$(state_from client_http_state "$client_output")

health_state=partial
next_action="inspect guide-router output"
if [ "$guide_exit" -ne 0 ]; then
  health_state=router_audit_failed
  next_action="fix SSH/router reachability, then rerun guide-router"
elif [ "${proxy_state:-}" != "absent" ] &&
  { [ "${self_heal_registration_state:-unknown}" != "ready" ] || [ "${self_heal_boot_hook_state:-unknown}" != "ready" ]; }; then
  health_state=lifecycle_registration_degraded
  next_action="repair project-owned boot and scheduler registration"
elif [ "${runtime_state:-}" = "authentication_blocked" ]; then
  health_state=controller_auth_blocked
  next_action="configure matching controller secret in router-local policy"
elif [ "${runtime_state:-}" = "controller_unreachable" ]; then
  health_state=runtime_unreachable
  next_action="inspect or start proxy runtime through its adapter or native interface"
elif [ "${proxy_state:-}" = "verified" ] && [ "${automation_state:-}" = "live_managed" ]; then
  health_state=router_managed
  next_action=none
elif [ "${proxy_state:-}" = "verified" ]; then
  health_state=router_usable
  next_action="enable live self-heal after dry-run review"
elif [ "${proxy_state:-}" = "api_reachable" ]; then
  health_state=runtime_needs_route_verification
  next_action="inspect self-heal dry-run and route status"
elif [ "${subscription_state:-}" = "missing" ]; then
  health_state=subscription_missing
  next_action="store provider subscription or import through ShellCrash"
fi

if [ "$client_exit" -ne 0 ]; then
  client_topology_mode=unknown
  client_runtime_present=unknown
  client_conflict_risk=unknown
  gateway_matches_router=unknown
  client_http_state=unknown
fi

edge_health_state_out=$health_state
device_state_out=$(or_unknown "${device_state:-}")
baseline_state_out=$(or_unknown "${baseline_state:-}")
proxy_state_out=$(or_unknown "${proxy_state:-}")
runtime_state_out=$(or_unknown "${runtime_state:-}")
controller_state_out=$(or_unknown "${controller_state:-}")
controller_auth_state_out=$(or_unknown "${controller_auth_state:-}")
self_heal_registration_state_out=$(or_unknown "${self_heal_registration_state:-}")
self_heal_boot_hook_state_out=$(or_unknown "${self_heal_boot_hook_state:-}")
subscription_state_out=$(or_unknown "${subscription_state:-}")
subscription_consumption_state_out=$(or_unknown "${subscription_consumption_state:-}")
automation_state_out=$(or_unknown "${automation_state:-}")
risk_count_out=$(or_unknown "${risk_count:-}")
review_count_out=$(or_unknown "${review_count:-}")
monitor_count_out=$(or_unknown "${monitor_count:-}")
client_topology_mode_out=$(or_unknown "${client_topology_mode:-}")
client_runtime_present_out=$(or_unknown "${client_runtime_present:-}")
client_conflict_risk_out=$(or_unknown "${client_conflict_risk:-}")
gateway_matches_router_out=$(or_unknown "${gateway_matches_router:-}")
client_http_state_out=$(or_unknown "${client_http_state:-}")
next_action_out=$next_action

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN { ORS="" } { if (NR > 1) printf "\\n"; gsub(/\r/, "\\r"); gsub(/\t/, "\\t"); gsub(/[[:cntrl:]]/, ""); printf "%s", $0 }'
}

json_pair() {
  key="$1"
  value="$2"
  suffix="$3"
  printf '  "%s": "%s"%s\n' "$key" "$(json_escape "$value")" "$suffix"
}

if [ "$json" -eq 1 ]; then
  printf '{\n'
  json_pair edge_health_state "$edge_health_state_out" ,
  json_pair device_state "$device_state_out" ,
  json_pair baseline_state "$baseline_state_out" ,
  json_pair proxy_state "$proxy_state_out" ,
  json_pair runtime_state "$runtime_state_out" ,
  json_pair controller_state "$controller_state_out" ,
  json_pair controller_auth_state "$controller_auth_state_out" ,
  json_pair self_heal_registration_state "$self_heal_registration_state_out" ,
  json_pair self_heal_boot_hook_state "$self_heal_boot_hook_state_out" ,
  json_pair subscription_state "$subscription_state_out" ,
  json_pair subscription_consumption_state "$subscription_consumption_state_out" ,
  json_pair automation_state "$automation_state_out" ,
  json_pair risk_count "$risk_count_out" ,
  json_pair review_count "$review_count_out" ,
  json_pair monitor_count "$monitor_count_out" ,
  json_pair client_topology_mode "$client_topology_mode_out" ,
  json_pair client_runtime_present "$client_runtime_present_out" ,
  json_pair client_conflict_risk "$client_conflict_risk_out" ,
  json_pair gateway_matches_router "$gateway_matches_router_out" ,
  json_pair client_http_state "$client_http_state_out" ,
  json_pair next_action "$next_action_out" ""
  printf '}\n'
  exit 0
fi

echo "# Edge Health Summary"
echo
echo "edge_health_state=$edge_health_state_out"
echo "device_state=$device_state_out"
echo "baseline_state=$baseline_state_out"
echo "proxy_state=$proxy_state_out"
echo "runtime_state=$runtime_state_out"
echo "controller_state=$controller_state_out"
echo "controller_auth_state=$controller_auth_state_out"
echo "self_heal_registration_state=$self_heal_registration_state_out"
echo "self_heal_boot_hook_state=$self_heal_boot_hook_state_out"
echo "subscription_state=$subscription_state_out"
echo "subscription_consumption_state=$subscription_consumption_state_out"
echo "automation_state=$automation_state_out"
echo "risk_count=$risk_count_out"
echo "review_count=$review_count_out"
echo "monitor_count=$monitor_count_out"
echo "client_topology_mode=$client_topology_mode_out"
echo "client_runtime_present=$client_runtime_present_out"
echo "client_conflict_risk=$client_conflict_risk_out"
echo "gateway_matches_router=$gateway_matches_router_out"
echo "client_http_state=$client_http_state_out"
echo "next_action=$next_action_out"
