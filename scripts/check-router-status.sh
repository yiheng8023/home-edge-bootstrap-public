#!/bin/sh
# Host-side status helper for macOS/Linux/Git Bash.
set -u

router="${1:-${ROUTER:-}}"
if [ -z "$router" ]; then
  echo "usage: sh scripts/check-router-status.sh <ssh-user>@<router-ip>" >&2
  echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
  exit 2
fi

log_path="${LOG_PATH:-/tmp/home-edge-router-status.log}"
known_hosts_file="${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}"
no_log="${NO_LOG:-0}"
ssh_opts="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts_file}"
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

expected_source_kind=unknown
expected_source_commit=unknown
expected_source_version=unknown
if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -z "$(git -C "$repo" status --porcelain --untracked-files=no)" ]; then
    expected_source_kind=git
    expected_source_commit=$(git -C "$repo" rev-parse HEAD)
  fi
elif [ -s "$repo/VERSION" ]; then
  candidate=$(sed -n '1p' "$repo/VERSION" | tr -d '\r')
  if printf '%s\n' "$candidate" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    expected_source_kind=release
    expected_source_version=$candidate
  fi
fi

mkdir -p "$(dirname "$log_path")" "$(dirname "$known_hosts_file")"

remote_script='probe_api() {
  u="${1%/}"
  [ -n "$u" ] || return 0
  case " $seen_api " in *" $u "*) return 0 ;; esac
  seen_api="$seen_api $u"
  printf "%s " "$u"
  curl -s --connect-timeout 2 --max-time 4 "$u/version" || true
  echo
}

echo "--- deployment provenance ---"
if [ -r /jffs/home-edge-bootstrap/scripts/verify-deployment-provenance.sh ]; then
  HOME_EDGE_EXPECTED_SOURCE_KIND=__EXPECTED_KIND__ \
  HOME_EDGE_EXPECTED_SOURCE_COMMIT=__EXPECTED_COMMIT__ \
  HOME_EDGE_EXPECTED_SOURCE_VERSION=__EXPECTED_VERSION__ \
    sh /jffs/home-edge-bootstrap/scripts/verify-deployment-provenance.sh
else
  echo "deployment_provenance_state=missing"
  echo "deployment_source_commit=unavailable"
  echo "deployment_source_version=unavailable"
  echo "deployment_source_tree_state=unavailable"
  echo "deployment_content_id=unavailable"
fi

echo "--- date ---"
date
echo "--- stable state ---"
stable_state_root=/jffs/home-edge-bootstrap-state
stable_schema_file=$stable_state_root/lifecycle/state.env
stable_subscription_file=$stable_state_root/SUBSCRIPTION.local
stable_policy_file=$stable_state_root/policy.local
compatibility_bridge=/jffs/scripts/home-edge-policy.local
echo "stable_state_root=$stable_state_root"
if [ ! -e "$stable_schema_file" ]; then
  echo "stable_state_schema=missing"
elif [ ! -r "$stable_schema_file" ]; then
  echo "stable_state_schema=invalid"
else
  schema_version=$(sed -n "s/^state_schema_version=//p" "$stable_schema_file" | head -n 1)
  schema_root=$(sed -n "s/^stable_state_root=//p" "$stable_schema_file" | head -n 1)
  if [ "$schema_version" = 1 ] && [ "$schema_root" = "$stable_state_root" ]; then
    echo "stable_state_schema=1"
  else
    echo "stable_state_schema=invalid"
  fi
fi
if [ -s "$stable_subscription_file" ]; then
  echo "stable_subscription_state=present"
elif [ -e "$stable_subscription_file" ]; then
  echo "stable_subscription_state=unavailable"
else
  echo "stable_subscription_state=absent"
fi
if [ -s "$stable_policy_file" ]; then
  echo "stable_policy_state=present"
elif [ -e "$stable_policy_file" ]; then
  echo "stable_policy_state=unavailable"
else
  echo "stable_policy_state=absent"
fi
bridge_expected=$(printf "%s\n" \
  "# home-edge-bootstrap-owned: stable-state-compatibility/v1" \
  "SUBSCRIPTION_FILE=/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local" \
  "SUBSCRIPTION_CACHE=/jffs/home-edge-bootstrap-state/cache/subscription.yaml" \
  "SUBSCRIPTION_BACKUP_DIR=/jffs/home-edge-bootstrap-state/backups/subscription" \
  "[ ! -r /jffs/home-edge-bootstrap-state/policy.local ] || . /jffs/home-edge-bootstrap-state/policy.local")
if [ ! -e "$compatibility_bridge" ]; then
  echo "compatibility_bridge_state=absent"
elif [ ! -r "$compatibility_bridge" ]; then
  echo "compatibility_bridge_state=drift"
elif [ "$(cat "$compatibility_bridge" 2>/dev/null)" = "$bridge_expected" ]; then
  echo "compatibility_bridge_state=present"
else
  echo "compatibility_bridge_state=drift"
fi
echo "--- policy ---"
[ -r /jffs/scripts/home-edge-policy.env ] && echo "managed_policy_state=present" || echo "managed_policy_state=absent"
echo "--- cron ---"
cru l | grep "home_edge_selfheal" || true
echo "--- lifecycle registration ---"
if [ -x /jffs/scripts/home-edge-reconcile-self-heal.sh ]; then
  sh /jffs/scripts/home-edge-reconcile-self-heal.sh --status || true
else
  echo "self_heal_registration_state=missing"
  echo "self_heal_boot_hook_state=missing"
  echo "self_heal_policy_mode=unknown"
fi
echo "--- controller observation ---"
runtime_process_state=unknown
runtime_active_config_path=unknown
if command -v pidof >/dev/null 2>&1; then
  runtime_process_state=not_detected
  for runtime_name in mihomo clash CrashCore sing-box; do
    if runtime_pids=$(pidof "$runtime_name" 2>/dev/null); then
      runtime_process_state=running
      for runtime_pid in $runtime_pids; do
        candidate_config=$(tr "\000" "\n" <"/proc/$runtime_pid/cmdline" 2>/dev/null | awk "take { print; exit } \$0 == \"-f\" || \$0 == \"--config\" { take=1; next } /^--config=\\// { sub(/^--config=/, \"\"); print; exit } /^-f\\// { sub(/^-f/, \"\"); print; exit }")
        case "$candidate_config" in /*) runtime_active_config_path=$candidate_config; break ;; esac
      done
      break
    fi
  done
fi
echo "runtime_process_state=$runtime_process_state"
runtime_process_identity=unknown
runtime_process_start_epoch=unknown
runtime_evidence_helper=/jffs/scripts/home-edge-subscription-runtime-evidence.sh
if [ -x "$runtime_evidence_helper" ]; then
  runtime_evidence_observation=$(sh "$runtime_evidence_helper" observe 2>/dev/null || true)
  runtime_process_identity=$(printf "%s\n" "$runtime_evidence_observation" | sed -n "s/^runtime_process_identity=//p" | head -n 1)
  runtime_process_start_epoch=$(printf "%s\n" "$runtime_evidence_observation" | sed -n "s/^runtime_process_start_epoch=//p" | head -n 1)
  observed_config=$(printf "%s\n" "$runtime_evidence_observation" | sed -n "s/^runtime_active_config_path=//p" | head -n 1)
  [ -z "$observed_config" ] || runtime_active_config_path=$observed_config
fi
echo "runtime_active_config_path=$runtime_active_config_path"
echo "runtime_process_identity=$runtime_process_identity"
echo "runtime_process_start_epoch=$runtime_process_start_epoch"
if [ -x /jffs/scripts/home-edge-self-heal.sh ]; then
  controller_output=$(HEAL_OBSERVE_ONLY=1 HEAL_LOG_OVERRIDE=/dev/null sh /jffs/scripts/home-edge-self-heal.sh 2>/dev/null || true)
  printf "%s\n" "$controller_output"
  controller_dashboard_config_state=$(printf "%s\n" "$controller_output" | sed -n "s/^dashboard_config_state=//p" | head -n 1)
  controller_observation_state=$(printf "%s\n" "$controller_output" | sed -n "s/^controller_observation_state=//p" | head -n 1)
  route_output=$(HEAL_VERIFY_ONLY=1 HEAL_LOG_OVERRIDE=/dev/null sh /jffs/scripts/home-edge-self-heal.sh 2>/dev/null || true)
  route_value() { printf "%s\n" "$route_output" | sed -n "s/^$1=//p" | head -n 1; }
  echo "route_evidence_probe_id=$(route_value route_probe_id)"
  echo "route_evidence_identity=$(route_value route_identity)"
  echo "route_evidence_classification=$(route_value route_classification)"
  route_verification_state=$(route_value verification_state)
  echo "route_evidence_verification_state=$route_verification_state"
else
  echo "controller_state=unknown"
  echo "controller_auth_state=unknown"
  echo "controller_observation_state=missing_observer"
fi
echo "--- files ---"
  ls -l /jffs/scripts/home-edge-self-heal.sh /jffs/scripts/home-edge-update-sub.sh /jffs/scripts/home-edge-self-heal-cron.sh /jffs/scripts/home-edge-reconcile-self-heal.sh /jffs/scripts/home-edge-policy.env /jffs/scripts/services-start 2>/dev/null || true
echo "--- subscription ---"
sub_file=/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local
sub_cache=/jffs/home-edge-bootstrap-state/cache/subscription.yaml
sub_backup_dir=/jffs/home-edge-bootstrap-state/backups/subscription
if [ -s "$sub_file" ]; then
  echo "subscription_file=present"
else
  echo "subscription_file=missing"
fi
if [ -s "$sub_cache" ]; then
  echo "subscription_cache=present"
else
  echo "subscription_cache=missing"
fi
subscription_apply_path=$(SUBSCRIPTION_APPLY_PATH=""; for f in /jffs/scripts/home-edge-policy.env /jffs/home-edge-bootstrap-state/policy.local; do [ ! -r "$f" ] || . "$f"; done; printf "%s" "${SUBSCRIPTION_APPLY_PATH:-}")
subscription_runtime_evidence=$(SUBSCRIPTION_RUNTIME_EVIDENCE="/tmp/home-edge-subscription-runtime.evidence"; for f in /jffs/scripts/home-edge-policy.env /jffs/home-edge-bootstrap-state/policy.local; do [ ! -r "$f" ] || . "$f"; done; printf "%s" "${SUBSCRIPTION_RUNTIME_EVIDENCE:-/tmp/home-edge-subscription-runtime.evidence}")
subscription_runtime_evidence_max_age=$(SUBSCRIPTION_RUNTIME_EVIDENCE_MAX_AGE_SEC=300; for f in /jffs/scripts/home-edge-policy.env /jffs/home-edge-bootstrap-state/policy.local; do [ ! -r "$f" ] || . "$f"; done; printf "%s" "${SUBSCRIPTION_RUNTIME_EVIDENCE_MAX_AGE_SEC:-300}")
if [ -s "$sub_cache" ] && [ -n "$subscription_apply_path" ]; then
  if [ ! -s "$subscription_apply_path" ]; then
    echo "subscription_consumption_state=live_profile_missing"
  elif [ "$sub_cache" = "$subscription_apply_path" ]; then
    echo "subscription_consumption_state=cache_apply_path_alias"
  elif command -v cmp >/dev/null 2>&1 && cmp -s "$sub_cache" "$subscription_apply_path" 2>/dev/null; then
    consumption_state=profile_file_matches_cache
    if [ -x "$runtime_evidence_helper" ] && [ "$runtime_active_config_path" = "$subscription_apply_path" ] &&
      [ "${controller_observation_state:-}" = ready ] && [ "${route_verification_state:-}" = pass ]; then
      classifier_output=$(HOME_EDGE_SUB_CACHE="$sub_cache" HOME_EDGE_SUB_APPLY_PATH="$subscription_apply_path" \
        HOME_EDGE_SUB_EVIDENCE="$subscription_runtime_evidence" HOME_EDGE_RUNTIME_PROCESS_IDENTITY="$runtime_process_identity" \
        HOME_EDGE_RUNTIME_PROCESS_START_EPOCH="$runtime_process_start_epoch" HOME_EDGE_EVIDENCE_MAX_AGE_SEC="$subscription_runtime_evidence_max_age" \
        sh "$runtime_evidence_helper" classify 2>/dev/null || true)
      classified_state=$(printf "%s\n" "$classifier_output" | sed -n "s/^subscription_consumption_state=//p" | head -n 1)
      [ -z "$classified_state" ] || consumption_state=$classified_state
    fi
    echo "subscription_consumption_state=$consumption_state"
  elif command -v cmp >/dev/null 2>&1; then
    echo "subscription_consumption_state=live_profile_differs_from_cache"
  else
    echo "subscription_consumption_state=live_profile_comparison_unavailable"
  fi
elif [ -s "$sub_cache" ]; then
  echo "subscription_consumption_state=cache_only_unverified"
else
  echo "subscription_consumption_state=not_observed"
fi
if [ -d "$sub_backup_dir" ]; then
  echo "subscription_backup_count=$(ls "$sub_backup_dir" 2>/dev/null | wc -l | tr -d " ")"
else
  echo "subscription_backup_count=0"
fi
echo "--- subscription log ---"
tail -n 10 /tmp/update-sub.log 2>/dev/null || true
echo "--- mihomo api candidates ---"
seen_api=""
test -r /tmp/self-heal.api && probe_api "$(cat /tmp/self-heal.api 2>/dev/null)"
for u in \
  http://127.0.0.1:9090 \
  http://127.0.0.1:9999 \
  http://127.0.0.1:9097 \
  http://127.0.0.1:9091 \
  http://127.0.0.1:9098 \
  http://127.0.0.1:10090 \
  http://127.0.0.1:19090
do
  probe_api "$u"
done
echo "--- dashboard evidence ---"
dashboard_config_state=${controller_dashboard_config_state:-unknown}
for runtime_config in /etc/ShellClash/config.yaml /etc/ShellClash/config.yml /jffs/ShellClash/config.yaml /jffs/ShellCrash/config.yaml /jffs/ShellCrash/config.yml /jffs/ShellCrash/yamls/config.yaml /jffs/ShellCrash/yamls/config.yml /jffs/shellclash/config.yaml /tmp/ShellClash/config.yaml /tmp/shellclash/config.yaml /etc/clash/config.yaml /tmp/clash/config.yaml /jffs/clash/config.yaml; do
  if [ -r "$runtime_config" ] && grep -Eq '^[[:space:]]*external-ui[[:space:]]*:[[:space:]]*[^#[:space:]]' "$runtime_config"; then
    dashboard_config_state=configured
    break
  fi
done
echo "dashboard_config_state=$dashboard_config_state"
echo "dashboard_reachability_state=unverified"
echo "--- self-heal api cache ---"
test -r /tmp/self-heal.api && cat /tmp/self-heal.api || true
echo
echo "--- self-heal log ---"
tail -n 20 /tmp/self-heal.log 2>/dev/null || true'
remote_script=$(printf '%s' "$remote_script" | sed "s/__EXPECTED_KIND__/$expected_source_kind/g; s/__EXPECTED_COMMIT__/$expected_source_commit/g; s/__EXPECTED_VERSION__/$expected_source_version/g")

if [ "$no_log" = "1" ]; then
  if output=$(printf '%s' "$remote_script" | ssh $ssh_opts -- "$router" 'tr -d "\r" | sh -s'); then
    printf '%s\n' "$output"
    exit 0
  else
    status=$?
    printf '%s\n' "$output"
    exit "$status"
  fi
fi

printf '%s\n' "Router status log: $log_path"
if printf '%s' "$remote_script" | ssh $ssh_opts -- "$router" 'tr -d "\r" | sh -s' > "$log_path"; then
  cat "$log_path"
  exit 0
fi
status=$?
cat "$log_path" 2>/dev/null || true
exit "$status"
