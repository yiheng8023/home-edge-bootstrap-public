#!/bin/sh
# Read-only installation closeout check. Does not print subscription URLs.
set -u

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
router=${1:-}
client_confirmed=0
run_client_check=0
client_check_url=${CLIENT_CHECK_URL:-https://cp.cloudflare.com/generate_204}
accept_runtime_imported_subscription=0
accept_client_runtime=0
dashboard_confirmed=0

shift_count=0
if [ $# -gt 0 ]; then
  shift_count=1
fi
if [ "$shift_count" -eq 1 ]; then
  shift
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --client-confirmed)
      client_confirmed=1
      ;;
    --run-client-check)
      run_client_check=1
      ;;
    --client-check-url)
      shift
      if [ $# -eq 0 ]; then
        echo "--client-check-url requires a URL" >&2
        exit 2
      fi
      client_check_url=$1
      ;;
    --accept-runtime-imported-subscription)
      accept_runtime_imported_subscription=1
      ;;
    --accept-client-runtime)
      accept_client_runtime=1
      ;;
    --dashboard-confirmed)
      dashboard_confirmed=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$router" ]; then
  echo "Usage: sh scripts/check-installation-closeout.sh <user@router-lan-ip> [--client-confirmed|--run-client-check] [--accept-runtime-imported-subscription] [--dashboard-confirmed] [--accept-client-runtime]" >&2
  exit 2
fi

router_host=${router##*@}
client_evidence=""

get_state() {
  key=$1
  printf '%s\n' "$guide_output" | awk -F= -v key="$key" '$1 == key { value=$0; sub("^[^=]*=", "", value); print value; exit }'
}
get_status_state() {
  key=$1
  printf '%s\n' "$status_output" | awk -F= -v key="$key" '$1 == key { value=$0; sub("^[^=]*=", "", value); print value; exit }'
}

echo "# Installation Closeout Check"
echo

if repository_output=$(sh "$repo/scripts/verify-closeout.sh" 2>&1); then
  if printf '%s\n' "$repository_output" | grep -q '^closeout_state=ready$'; then
    repository_gate=pass
  else
    repository_gate=fail
  fi
else
  repository_gate=fail
fi

guide_exit=0
guide_output=$(sh "$repo/scripts/guide-router.sh" "$router" 2>&1) || guide_exit=$?

status_exit=0
status_output=$(sh "$repo/scripts/check-router-status.sh" "$router" 2>&1) || status_exit=$?

device_state=$(get_state device_state)
admin_state=$(get_state admin_state)
baseline_state=$(get_state baseline_state)
proxy_state=$(get_state proxy_state)
runtime_state=$(get_state runtime_state)
runtime_process_state=$(get_state runtime_process_state)
controller_observation_state=$(get_state controller_observation_state)
controller_auth_state=$(get_state controller_auth_state)
self_heal_registration_state=$(get_state self_heal_registration_state)
self_heal_boot_hook_state=$(get_state self_heal_boot_hook_state)
subscription_state=$(get_state subscription_state)
subscription_consumption_state=$(get_state subscription_consumption_state)
dashboard_config_state=$(get_state dashboard_config_state)
dashboard_reachability_state=$(get_state dashboard_reachability_state)
automation_state=$(get_state automation_state)
risk_count=$(get_state risk_count)
review_count=$(get_state review_count)
monitor_count=$(get_state monitor_count)

router_gate=fail
if [ "$guide_exit" -eq 0 ] &&
  [ "$device_state" = "ssh_reachable" ] &&
  [ "$admin_state" = "jffs_scripts_ready" ] &&
  { [ "$baseline_state" = "reviewed" ] || [ "$baseline_state" = "reviewed_with_monitoring" ]; } &&
  [ "$risk_count" = "0" ] &&
  [ "$review_count" = "0" ]; then
  router_gate=pass
fi

dashboard_gate=fail
dashboard_evidence=unverified
if [ "$dashboard_config_state" = "not_configured" ]; then
  dashboard_gate=not_applicable
  dashboard_evidence=not_applicable
elif [ "$dashboard_config_state" = "configured" ] && [ "$dashboard_reachability_state" = "ready" ]; then
  dashboard_gate=pass
  dashboard_evidence=observed_ready
elif [ "$dashboard_config_state" = "configured" ] && [ "$dashboard_reachability_state" = "unverified" ] && [ "$dashboard_confirmed" -eq 1 ]; then
  dashboard_gate=pass
  dashboard_evidence=user_confirmed
elif [ "$dashboard_config_state" = "configured" ]; then
  dashboard_gate=reachability_unverified
else
  dashboard_gate=configuration_unknown
fi

runtime_gate=fail
if [ "$guide_exit" -eq 0 ] &&
  [ "$status_exit" -eq 0 ] &&
  [ "$proxy_state" = "verified" ] &&
  [ "$runtime_state" = "running" ] &&
  [ "$runtime_process_state" = "running" ] &&
  [ "$controller_observation_state" = "ready" ] &&
  { [ "$controller_auth_state" = "authenticated" ] || [ "$controller_auth_state" = "not_required" ]; } &&
  [ "$self_heal_registration_state" = "ready" ] &&
  [ "$self_heal_boot_hook_state" = "ready" ] &&
  [ "$automation_state" = "live_managed" ]; then
  runtime_gate=pass
fi

route_gate=fail
route_evidence_probe_id=$(get_status_state route_evidence_probe_id)
route_evidence_identity=$(get_status_state route_evidence_identity)
route_evidence_classification=$(get_status_state route_evidence_classification)
route_evidence_verification_state=$(get_status_state route_evidence_verification_state)
if [ -n "$route_evidence_probe_id" ] && [ -n "$route_evidence_identity" ] &&
  [ "$route_evidence_verification_state" = "pass" ]; then
  case "$route_evidence_classification" in
    reachable|region_match) route_gate=pass ;;
  esac
fi

subscription_gate=fail
if [ "$subscription_consumption_state" = "runtime_profile_matches_cache" ]; then
  subscription_gate=pass
elif [ "$subscription_state" = "missing" ]; then
  subscription_gate=missing
elif [ "$accept_runtime_imported_subscription" -eq 1 ] &&
  { [ "$subscription_consumption_state" = "manual_runtime_import_unverified" ] || [ "$subscription_consumption_state" = "cache_only_unverified" ] || [ "$subscription_consumption_state" = "profile_file_matches_cache" ]; }; then
  subscription_gate=accepted_manual_boundary
else
  subscription_gate=consumption_unverified
fi

if [ "$client_confirmed" -eq 1 ]; then
  client_gate=pass
  client_evidence=user_confirmed
elif [ "$run_client_check" -eq 1 ]; then
  client_topology_output=$(CLIENT_CHECK_URL="$client_check_url" sh "$repo/scripts/check-client-topology.sh" "$router" 2>&1)
  client_topology_mode=$(printf '%s\n' "$client_topology_output" | awk -F= '$1 == "client_topology_mode" { print $2; exit }')
  client_runtime_present=$(printf '%s\n' "$client_topology_output" | awk -F= '$1 == "client_runtime_present" { print $2; exit }')
  gateway_matches_router=$(printf '%s\n' "$client_topology_output" | awk -F= '$1 == "gateway_matches_router" { print $2; exit }')
  client_http_state=$(printf '%s\n' "$client_topology_output" | awk -F= '$1 == "client_http_state" { print $2; exit }')
  client_conflict_risk=$(printf '%s\n' "$client_topology_output" | awk -F= '$1 == "client_conflict_risk" { print $2; exit }')
  client_evidence="topology=${client_topology_mode:-unknown} runtime_present=${client_runtime_present:-unknown} gateway_matches_router=${gateway_matches_router:-unknown} http=${client_http_state:-unknown} conflict_risk=${client_conflict_risk:-unknown}"

  if [ "${client_runtime_present:-0}" = "1" ]; then
    if [ "$accept_client_runtime" -eq 1 ]; then
      client_gate=accepted_client_runtime
    else
      client_gate=client_runtime_present
    fi
  elif [ "${client_runtime_present:-unknown}" != "0" ]; then
    client_gate=client_runtime_unknown
  elif [ "${gateway_matches_router:-unknown}" != "yes" ]; then
    client_gate=fail
  else
    case "$client_http_state" in
      ok:*) client_gate=pass ;;
      *) client_gate=fail ;;
    esac
  fi
else
  client_gate=manual_required
fi

all_technical_pass=0
if [ "$repository_gate" = "pass" ] &&
  [ "$router_gate" = "pass" ] &&
  [ "$runtime_gate" = "pass" ] &&
  [ "$route_gate" = "pass" ]; then
  all_technical_pass=1
fi

subscription_accepted=0
if [ "$subscription_gate" = "pass" ] || [ "$subscription_gate" = "accepted_manual_boundary" ]; then
  subscription_accepted=1
fi

client_accepted=0
if [ "$client_gate" = "pass" ] || [ "$client_gate" = "accepted_client_runtime" ]; then
  client_accepted=1
fi

dashboard_accepted=0
if [ "$dashboard_gate" = "pass" ] || [ "$dashboard_gate" = "not_applicable" ]; then
  dashboard_accepted=1
fi

installation_closeout_state=partial
if [ "$all_technical_pass" -eq 1 ] && [ "$subscription_accepted" -eq 1 ] && [ "$client_accepted" -eq 1 ] && [ "$dashboard_accepted" -eq 1 ]; then
  if [ "$subscription_gate" = "pass" ] && [ "$client_gate" = "pass" ] && { [ "$dashboard_gate" = "pass" ] || [ "$dashboard_gate" = "not_applicable" ]; }; then
    installation_closeout_state=pass
  else
    installation_closeout_state=accepted_boundary
  fi
elif [ "$all_technical_pass" -ne 1 ]; then
  installation_closeout_state=fail
fi

echo "repository_gate=$repository_gate"
echo "router_gate=$router_gate"
echo "runtime_gate=$runtime_gate"
echo "route_gate=$route_gate"
echo "subscription_gate=$subscription_gate"
echo "dashboard_gate=$dashboard_gate"
echo "dashboard_evidence=$dashboard_evidence"
echo "client_gate=$client_gate"
echo "installation_closeout_state=$installation_closeout_state"
echo
echo "device_state=${device_state:-unknown}"
echo "admin_state=${admin_state:-unknown}"
echo "baseline_state=${baseline_state:-unknown}"
echo "proxy_state=${proxy_state:-unknown}"
echo "runtime_state=${runtime_state:-unknown}"
echo "runtime_process_state=${runtime_process_state:-unknown}"
echo "controller_observation_state=${controller_observation_state:-unknown}"
echo "controller_auth_state=${controller_auth_state:-unknown}"
echo "self_heal_registration_state=${self_heal_registration_state:-unknown}"
echo "self_heal_boot_hook_state=${self_heal_boot_hook_state:-unknown}"
echo "subscription_state=${subscription_state:-unknown}"
echo "subscription_consumption_state=${subscription_consumption_state:-unknown}"
echo "dashboard_config_state=${dashboard_config_state:-unknown}"
echo "dashboard_reachability_state=${dashboard_reachability_state:-unknown}"
echo "automation_state=${automation_state:-unknown}"
echo "route_evidence_probe_id=${route_evidence_probe_id:-unknown}"
echo "route_evidence_identity=${route_evidence_identity:-unknown}"
echo "route_evidence_classification=${route_evidence_classification:-unknown}"
echo "route_evidence_verification_state=${route_evidence_verification_state:-unknown}"
echo "monitor_count=${monitor_count:-unknown}"
if [ -n "$client_evidence" ]; then
  echo "client_evidence=$client_evidence"
fi
echo

if [ "$installation_closeout_state" = "pass" ] || [ "$installation_closeout_state" = "accepted_boundary" ]; then
  echo "next_action=none"
elif [ "$all_technical_pass" -ne 1 ]; then
  echo "next_action=inspect guide-router and check-router-status output, then fix the earliest failing gate"
elif [ "$subscription_gate" = "consumption_unverified" ] || [ "$subscription_gate" = "missing" ]; then
  echo "next_action=prove the validated cache is the live runtime profile, or rerun with --accept-runtime-imported-subscription only when manual ShellCrash import is intentionally accepted and separately verified"
elif [ "$dashboard_gate" = "reachability_unverified" ]; then
  echo "next_action=verify the configured native dashboard is reachable, then rerun with --dashboard-confirmed to record that verified human evidence"
elif [ "$client_gate" = "manual_required" ]; then
  echo "next_action=confirm from a client device that the configured probe target or another strict external target opens through this router, or rerun with --run-client-check on a computer whose default gateway is this router"
elif [ "$client_gate" = "client_runtime_present" ]; then
  echo "next_action=temporarily disable the local client proxy/TUN or make its policy intentionally equivalent, then rerun; use --accept-client-runtime only for an intentional fallback or hybrid topology"
elif [ "$client_gate" = "client_runtime_unknown" ]; then
  echo "next_action=rerun the read-only client topology check from a host where proxy, DNS, and route inspection are available; unknown evidence cannot pass pure router verification"
elif [ "$client_gate" = "fail" ]; then
  echo "next_action=run the client check on a computer whose default gateway is this router, or confirm manually from a client device and rerun with --client-confirmed"
else
  echo "next_action=inspect guide-router and check-router-status output, then fix the earliest failing gate"
fi

if [ "$installation_closeout_state" = "pass" ] || [ "$installation_closeout_state" = "accepted_boundary" ]; then
  exit 0
fi
exit 1
