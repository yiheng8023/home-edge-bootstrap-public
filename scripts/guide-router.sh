#!/bin/sh
# Host-side guided state loop for macOS/Linux/Git Bash.
set -u

router="${ROUTER:-}"
json=0
case "${GUIDE_ROUTER_JSON:-0}" in
  1|true|TRUE|yes|YES) json=1 ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      json=1
      ;;
    --help|-h)
      echo "usage: sh scripts/guide-router.sh [--json] <ssh-user>@<router-ip>" >&2
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
  echo "usage: sh scripts/guide-router.sh [--json] <ssh-user>@<router-ip>" >&2
  echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
  exit 2
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
log_path="${LOG_PATH:-/tmp/home-edge-router-guide-audit.log}"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN { ORS="" } { if (NR > 1) printf "\\n"; gsub(/\r/, "\\r"); gsub(/\t/, "\\t"); gsub(/[[:cntrl:]]/, ""); printf "%s", $0 }'
}

json_pair() {
  key="$1"
  value="$2"
  suffix="$3"
  printf '  "%s": "%s"%s\n' "$key" "$(json_escape "$value")" "$suffix"
}

if [ -n "${GUIDE_ROUTER_FIXTURE_AUDIT_OUTPUT+x}" ]; then
  mkdir -p "$(dirname "$log_path")"
  printf '%s\n' "$GUIDE_ROUTER_FIXTURE_AUDIT_OUTPUT" >"$log_path"
  status=${GUIDE_ROUTER_FIXTURE_AUDIT_EXIT:-0}
else
  if [ "$json" -eq 1 ]; then
    audit_output=$(LOG_PATH="$log_path" sh "$script_dir/audit-router-baseline.sh" "$router" 2>&1)
    status=$?
  else
    LOG_PATH="$log_path" sh "$script_dir/audit-router-baseline.sh" "$router"
    status=$?
  fi
fi

if [ "$status" -ne 0 ]; then
  if [ "$json" -eq 1 ]; then
    printf '{\n'
    json_pair guide_state audit_failed ,
    json_pair next_action_code fix_router_reachability ,
    json_pair next_action_command "sh scripts/guide-router.sh \"$router\"" ,
    json_pair audit_log_path "$log_path" ,
    json_pair audit_exit_code "$status" ,
    json_pair audit_error "${audit_output:-}" ""
    printf '}\n'
    exit "$status"
  fi
  echo
  echo "Guide stopped: audit failed with exit code $status."
  echo "Fix SSH/router reachability, then rerun this guide."
  exit "$status"
fi

get_state() {
  key="$1"
  grep -m1 "^$key=" "$log_path" 2>/dev/null | sed "s/^$key=//"
}

device_state=$(get_state device_state)
firmware_state=$(get_state firmware_state)
admin_state=$(get_state admin_state)
baseline_state=$(get_state baseline_state)
proxy_state=$(get_state proxy_state)
runtime_state=$(get_state runtime_state)
runtime_process_state=$(get_state runtime_process_state)
controller_state=$(get_state controller_state)
controller_auth_state=$(get_state controller_auth_state)
controller_observation_state=$(get_state controller_observation_state)
self_heal_registration_state=$(get_state self_heal_registration_state)
self_heal_boot_hook_state=$(get_state self_heal_boot_hook_state)
lifecycle_reconciler_state=$(get_state lifecycle_reconciler_state)
subscription_state=$(get_state subscription_state)
subscription_consumption_state=$(get_state subscription_consumption_state)
dashboard_config_state=$(get_state dashboard_config_state)
dashboard_reachability_state=$(get_state dashboard_reachability_state)
automation_state=$(get_state automation_state)
risk_count=$(get_state risk_count)
review_count=$(get_state review_count)
monitor_count=$(get_state monitor_count)

if [ -z "${device_state:-}" ]; then
  if [ "$json" -eq 1 ]; then
    printf '{\n'
    json_pair guide_state unreadable_audit ,
    json_pair next_action_code inspect_audit_log ,
    json_pair next_action_command "sh scripts/guide-router.sh \"$router\"" ,
    json_pair audit_log_path "$log_path" ""
    printf '}\n'
    exit 1
  fi
  echo
  echo "Guide stopped: audit log did not contain a readable state."
  echo "Inspect: $log_path"
  exit 1
fi

next_action_code=inspect_audit_log
next_action_command="sh scripts/guide-router.sh \"$router\""
next_action_text="State is incomplete or unknown. Inspect the audit log, then rerun:"

if [ "${admin_state:-}" != "jffs_scripts_ready" ]; then
  next_action_code=enable_router_prereqs
  next_action_command="sh scripts/guide-router.sh \"$router\""
  next_action_text="Open the router web UI, enable LAN SSH and JFFS custom scripts/configs, then rerun:"
elif [ "${baseline_state:-}" = "risky" ]; then
  next_action_code=resolve_action_findings
  next_action_command="sh scripts/guide-router.sh \"$router\""
  next_action_text="Resolve ACTION findings from the audit, then rerun:"
elif [ "${baseline_state:-}" = "needs_review" ]; then
  next_action_code=review_baseline_findings
  next_action_command="sh scripts/guide-router.sh \"$router\""
  next_action_text="Review REVIEW findings from the audit, decide the intended policy, then rerun:"
elif [ "${lifecycle_reconciler_state:-unknown}" = "absent" ]; then
  next_action_code=deploy_plan
  next_action_command="sh scripts/deploy-merlin.sh \"$router\""
  next_action_text="Upgrade the existing installation to deploy the lifecycle reconciler, then re-check state:"
elif [ "${proxy_state:-}" != "absent" ] &&
     { [ "${self_heal_registration_state:-unknown}" != "ready" ] || [ "${self_heal_boot_hook_state:-unknown}" != "ready" ]; }; then
  next_action_code=repair_self_heal_registration
  next_action_command="sh scripts/repair-self-heal-registration.sh \"$router\""
  next_action_text="Restore the project-owned boot hook and self-heal scheduler, then re-check state:"
elif [ "${runtime_state:-}" = "authentication_blocked" ]; then
  next_action_code=configure_controller_auth
  next_action_command="sh scripts/check-router-status.sh \"$router\""
  next_action_text="Configure the matching Mihomo controller secret in the router-local policy, then re-check without exposing it:"
elif [ "${runtime_state:-}" = "controller_unreachable" ]; then
  next_action_code=inspect_or_start_proxy_runtime
  next_action_command="sh scripts/check-router-status.sh \"$router\""
  next_action_text="Inspect ShellCrash/Mihomo runtime state and start or repair it through its adapter or native interface, then re-check:"
elif [ "${automation_state:-}" = "live_managed" ]; then
  if [ "${subscription_state:-}" = "missing" ] || [ "${subscription_state:-}" = "runtime_imported" ]; then
    next_action_code=store_subscription_for_managed_switching
    next_action_command="sh scripts/store-subscription.sh \"$router\""
    next_action_text="The router is live-managed. For scripted provider switching later, store the provider subscription on the router first:"
  else
    next_action_code=monitor_live_managed
    next_action_command="sh scripts/check-router-status.sh \"$router\""
    next_action_text="The router baseline and proxy path are already live-managed. Check status when needed:"
  fi
elif [ "${proxy_state:-}" = "absent" ]; then
  next_action_code=deploy_plan
  next_action_command="sh scripts/deploy-merlin.sh \"$router\""
  next_action_text="Run deploy plan first:"
elif [ "${proxy_state:-}" = "policy_deployed" ] || [ "${proxy_state:-}" = "self_heal_installed" ]; then
  next_action_code=store_or_import_subscription
  next_action_command="sh scripts/store-subscription.sh \"$router\""
  next_action_text="Store and refresh the provider subscription, or import/start it in ShellCrash, then check status:"
elif [ "${proxy_state:-}" = "api_reachable" ]; then
  next_action_code=inspect_self_heal_dry_run
  next_action_command="sh scripts/check-router-status.sh \"$router\""
  next_action_text="Run status and inspect DRY-RUN self-heal logs:"
elif [ "${proxy_state:-}" = "verified" ]; then
  next_action_code=enable_live_self_heal
  next_action_command="sh scripts/enable-live-self-heal.sh \"$router\""
  next_action_text="The router baseline and proxy path are usable. Confirm live self-heal when desired:"
fi

if [ "$json" -eq 1 ]; then
  printf '{\n'
  json_pair guide_state ready ,
  json_pair device_state "${device_state:-unknown}" ,
  json_pair firmware_state "${firmware_state:-unknown}" ,
  json_pair admin_state "${admin_state:-unknown}" ,
  json_pair baseline_state "${baseline_state:-unknown}" ,
  json_pair proxy_state "${proxy_state:-unknown}" ,
  json_pair runtime_state "${runtime_state:-unknown}" ,
  json_pair runtime_process_state "${runtime_process_state:-unknown}" ,
  json_pair controller_state "${controller_state:-unknown}" ,
  json_pair controller_auth_state "${controller_auth_state:-unknown}" ,
  json_pair controller_observation_state "${controller_observation_state:-unknown}" ,
  json_pair self_heal_registration_state "${self_heal_registration_state:-unknown}" ,
  json_pair self_heal_boot_hook_state "${self_heal_boot_hook_state:-unknown}" ,
  json_pair lifecycle_reconciler_state "${lifecycle_reconciler_state:-unknown}" ,
  json_pair subscription_state "${subscription_state:-unknown}" ,
  json_pair subscription_consumption_state "${subscription_consumption_state:-unknown}" ,
  json_pair dashboard_config_state "${dashboard_config_state:-unknown}" ,
  json_pair dashboard_reachability_state "${dashboard_reachability_state:-unknown}" ,
  json_pair automation_state "${automation_state:-unknown}" ,
  json_pair risk_count "${risk_count:-unknown}" ,
  json_pair review_count "${review_count:-unknown}" ,
  json_pair monitor_count "${monitor_count:-unknown}" ,
  json_pair next_action_code "$next_action_code" ,
  json_pair next_action_command "$next_action_command" ,
  json_pair audit_log_path "$log_path" ""
  printf '}\n'
  exit 0
fi

echo
echo "## Guided State Summary"
echo "guide_state=ready"
echo "device_state=${device_state:-unknown}"
echo "firmware_state=${firmware_state:-unknown}"
echo "admin_state=${admin_state:-unknown}"
echo "baseline_state=${baseline_state:-unknown}"
echo "proxy_state=${proxy_state:-unknown}"
echo "runtime_state=${runtime_state:-unknown}"
echo "runtime_process_state=${runtime_process_state:-unknown}"
echo "controller_state=${controller_state:-unknown}"
echo "controller_auth_state=${controller_auth_state:-unknown}"
echo "controller_observation_state=${controller_observation_state:-unknown}"
echo "self_heal_registration_state=${self_heal_registration_state:-unknown}"
echo "self_heal_boot_hook_state=${self_heal_boot_hook_state:-unknown}"
echo "lifecycle_reconciler_state=${lifecycle_reconciler_state:-unknown}"
echo "subscription_state=${subscription_state:-unknown}"
echo "subscription_consumption_state=${subscription_consumption_state:-unknown}"
echo "dashboard_config_state=${dashboard_config_state:-unknown}"
echo "dashboard_reachability_state=${dashboard_reachability_state:-unknown}"
echo "automation_state=${automation_state:-unknown}"
echo "risk_count=${risk_count:-unknown}"
echo "review_count=${review_count:-unknown}"
echo "monitor_count=${monitor_count:-unknown}"
echo "next_action_code=$next_action_code"
echo "next_action_command=$next_action_command"
echo "audit_log_path=$log_path"

echo
echo "## Suggested Next Command"
echo "$next_action_text"
echo "  $next_action_command"
if [ "$next_action_code" = "deploy_plan" ]; then
  echo "Then apply only after the plan looks right:"
  echo "  APPLY=1 sh scripts/deploy-merlin.sh \"$router\""
elif [ "$next_action_code" = "store_or_import_subscription" ]; then
  echo "  sh scripts/refresh-subscription.sh \"$router\""
  echo "  sh scripts/check-router-status.sh \"$router\""
elif [ "$next_action_code" = "enable_live_self_heal" ]; then
  echo "Then rerun:"
  echo "  sh scripts/check-router-status.sh \"$router\""
fi
