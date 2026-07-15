#!/bin/sh
# Host-side read-only router baseline audit for macOS/Linux/Git Bash.
set -u

router="${1:-${ROUTER:-}}"
if [ -z "$router" ]; then
  echo "usage: sh scripts/audit-router-baseline.sh <ssh-user>@<router-ip>" >&2
  echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
  exit 2
fi

log_path="${LOG_PATH:-/tmp/home-edge-router-baseline-audit.log}"
known_hosts_file="${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}"
ssh_timeout="${SSH_CONNECT_TIMEOUT_SEC:-8}"
ssh_opts="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=$ssh_timeout -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts_file}"

mkdir -p "$(dirname "$log_path")" "$(dirname "$known_hosts_file")"

remote_script='PATH="/sbin:/bin:/usr/sbin:/usr/bin:/jffs/scripts:/jffs/bin:/opt/bin:/opt/sbin:${PATH:-}"
export PATH

nv() { nvram get "$1" 2>/dev/null || true; }
has_cmd() {
  old_ifs=$IFS
  IFS=:
  for d in $PATH; do
    [ -n "$d" ] || d=.
    [ -x "$d/$1" ] && { IFS=$old_ifs; return 0; }
  done
  IFS=$old_ifs
  return 1
}

print_kv() { printf "%s=%s\n" "$1" "$2"; }
mark() { printf "[%s] %s\n" "$1" "$2"; }

probe_api() {
  u="${1%/}"
  [ -n "$u" ] || return 1
  case " $seen_api " in *" $u "*) return 1 ;; esac
  seen_api="$seen_api $u"
  r=$(curl -fsS --connect-timeout 2 --max-time 4 "$u/version" 2>/dev/null || true)
  if echo "$r" | grep -q "\"version\""; then
    api_url="$u"
    api_version=$(printf "%s" "$r" | sed "s/.*\"version\":\"//;s/\".*//")
    return 0
  fi
  r=$(curl -fsS --connect-timeout 2 --max-time 4 "$u/proxies" 2>/dev/null || true)
  if echo "$r" | grep -q "\"proxies\""; then
    api_url="$u"
    api_version="reachable"
    return 0
  fi
  return 1
}

discover_api() {
  api_url=""
  api_version=""
  seen_api=""
  [ -r /tmp/self-heal.api ] && probe_api "$(cat /tmp/self-heal.api 2>/dev/null)" && return 0
  for u in \
    http://127.0.0.1:9090 \
    http://127.0.0.1:9999 \
    http://127.0.0.1:9097 \
    http://127.0.0.1:9091 \
    http://127.0.0.1:9098 \
    http://127.0.0.1:10090 \
    http://127.0.0.1:19090
  do
    probe_api "$u" && return 0
  done
  return 1
}

productid=$(nv productid)
firmver=$(nv firmver)
buildno=$(nv buildno)
extendno=$(nv extendno)
sw_mode=$(nv sw_mode)
kernel=$(uname -a 2>/dev/null || true)
kernel_arch=$(uname -m 2>/dev/null || true)

firmware_state="unknown"
case "$kernel" in
  *KoolShare*) firmware_state="merlin_compatible_modified" ;;
  *ASUSWRT-Merlin*) firmware_state="official_merlin" ;;
  *ASUSWRT*) firmware_state="stock_asuswrt" ;;
esac
[ -n "$productid" ] || productid="unknown"

jffs_scripts=$(nv jffs2_scripts)
sshd_enable=$(nv sshd_enable)
sshd_port=$(nv sshd_port)
sshd_authkeys=$(nv sshd_authkeys)

device_state="ssh_reachable"
admin_state="ssh_reachable"
[ "$jffs_scripts" = "1" ] && [ -d /jffs/scripts ] && admin_state="jffs_scripts_ready"
[ -n "$sshd_authkeys" ] && ssh_auth_state="key_present" || ssh_auth_state="unknown_or_password"

wps_enable=$(nv wps_enable)
wl_wps_mode=$(nv wl_wps_mode)
wl0_wps_mode=$(nv wl0_wps_mode)
wl1_wps_mode=$(nv wl1_wps_mode)
upnp_enable=$(nv upnp_enable)
wan0_upnp_enable=$(nv wan0_upnp_enable)
pptpd_enable=$(nv pptpd_enable)
wgs_enable=$(nv wgs_enable)
wgs1_enable=$(nv wgs1_enable)
misc_ping_x=$(nv misc_ping_x)
ipv6_service=$(nv ipv6_service)
qos_enable=$(nv qos_enable)

risk_count=0
review_count=0
monitor_count=0

echo "# Home Edge Router Baseline Audit"
echo
echo "## Date"
date
echo
echo "## State"
print_kv "device_state" "$device_state"
print_kv "firmware_state" "$firmware_state"
print_kv "admin_state" "$admin_state"
print_kv "ssh_auth_state" "$ssh_auth_state"
print_kv "productid" "$productid"
print_kv "firmware" "${firmver:-unknown}.${buildno:-unknown}_${extendno:-unknown}"
print_kv "kernel_arch" "${kernel_arch:-unknown}"
print_kv "sw_mode" "${sw_mode:-unknown}"
echo
echo "## Router Administration"
print_kv "sshd_enable" "${sshd_enable:-unknown}"
print_kv "sshd_port" "${sshd_port:-unknown}"
print_kv "jffs2_scripts" "${jffs_scripts:-unknown}"
if [ "$jffs_scripts" = "1" ] && [ -d /jffs/scripts ]; then
  mark OK "JFFS custom scripts are available."
else
  mark ACTION "Enable JFFS custom scripts/configs before automation can manage router scripts."
  risk_count=$((risk_count + 1))
fi
echo
echo "## Baseline Findings"
if [ "$wps_enable" = "0" ] && [ "$wl_wps_mode" = "disabled" ] && [ "$wl0_wps_mode" = "disabled" ] && [ "$wl1_wps_mode" = "disabled" ]; then
  mark OK "WPS is disabled."
else
  mark ACTION "WPS appears enabled; recommended baseline is disabled."
  risk_count=$((risk_count + 1))
fi

if [ "$pptpd_enable" = "1" ]; then
  mark ACTION "PPTP server is enabled; disable unless a legacy client explicitly requires it."
  risk_count=$((risk_count + 1))
else
  mark OK "PPTP server is disabled."
fi

if [ "$upnp_enable" = "1" ] || [ "$wan0_upnp_enable" = "1" ]; then
  mark MONITOR "UPnP is enabled; acceptable when gaming, communication apps, or downloaders need it, but audit active mappings."
  monitor_count=$((monitor_count + 1))
else
  mark OK "UPnP is disabled."
fi

if [ "$misc_ping_x" = "0" ]; then
  mark OK "WAN ping response is disabled."
else
  mark REVIEW "WAN ping response may be enabled; confirm this is intentional."
  review_count=$((review_count + 1))
fi

if [ "$ipv6_service" = "disabled" ] || [ -z "$ipv6_service" ]; then
  mark OK "IPv6 is disabled or unset; this is acceptable for a simple proxy/leak-control profile."
else
  mark REVIEW "IPv6 is enabled; verify firewall, DNS, and proxy leak policy."
  review_count=$((review_count + 1))
fi

if [ "$wgs_enable" = "1" ] || [ "$wgs1_enable" = "1" ]; then
  mark OK "WireGuard server appears enabled; keep peer keys and exposure under review."
else
  mark INFO "WireGuard server is not enabled."
fi

[ "$qos_enable" = "1" ] && mark INFO "QoS is enabled; keep if it improves local network traffic, retest if throughput suffers." || mark INFO "QoS is disabled."
echo
echo "## Required Tooling"
for tool in sh nvram cru curl grep sed awk sort wc date; do
  if has_cmd "$tool"; then
    print_kv "tool_$tool" "present"
  else
    print_kv "tool_$tool" "missing"
    risk_count=$((risk_count + 1))
  fi
done
for tool in tar gzip base64; do
  if has_cmd "$tool"; then
    print_kv "tool_$tool" "present"
  else
    print_kv "tool_$tool" "missing"
    risk_count=$((risk_count + 1))
  fi
done
for tool in sha256sum mktemp; do
  if has_cmd "$tool"; then
    print_kv "tool_$tool" "present"
  else
    print_kv "tool_$tool" "missing_recommended"
  fi
done
echo
echo "## Network Exposure Snapshot"
netstat -lntup 2>/dev/null | grep -E ":(22|80|443|8443|1723|51820)" || true
echo
echo "## UPnP Active Mappings"
iptables -S FUPNP 2>/dev/null || true
echo
echo "## Proxy Runtime"
proxy_state="absent"
api_reachable=0
[ -s /jffs/scripts/home-edge-self-heal.sh ] && proxy_state="policy_deployed"
cron_installed=0
cron_list=$(cru l 2>/dev/null || true)
if printf "%s\n" "$cron_list" | grep -q "home_edge_selfheal"; then
  cron_installed=1
fi
controller_state="unknown"
controller_auth_state="unknown"
controller_observation_state="unknown"
runtime_process_state="unknown"
runtime_active_config_path="unknown"
if has_cmd pidof; then
  runtime_process_state="not_detected"
  for runtime_name in mihomo clash CrashCore sing-box; do
    if runtime_pids=$(pidof "$runtime_name" 2>/dev/null); then
      runtime_process_state="running"
      for runtime_pid in $runtime_pids; do
        candidate_config=$(tr "\000" "\n" <"/proc/$runtime_pid/cmdline" 2>/dev/null | awk "take { print; exit } \$0 == \"-f\" || \$0 == \"--config\" { take=1; next } /^--config=\\// { sub(/^--config=/, \"\"); print; exit } /^-f\\// { sub(/^-f/, \"\"); print; exit }")
        case "$candidate_config" in /*) runtime_active_config_path=$candidate_config; break ;; esac
      done
      break
    fi
  done
fi
runtime_process_identity=""
runtime_process_start_epoch=""
runtime_evidence_helper=/jffs/scripts/home-edge-subscription-runtime-evidence.sh
if [ -x "$runtime_evidence_helper" ]; then
  runtime_evidence_observation=$(sh "$runtime_evidence_helper" observe 2>/dev/null || true)
  runtime_process_identity=$(printf "%s\n" "$runtime_evidence_observation" | sed -n "s/^runtime_process_identity=//p" | head -n 1)
  runtime_process_start_epoch=$(printf "%s\n" "$runtime_evidence_observation" | sed -n "s/^runtime_process_start_epoch=//p" | head -n 1)
  observed_config=$(printf "%s\n" "$runtime_evidence_observation" | sed -n "s/^runtime_active_config_path=//p" | head -n 1)
  case "$observed_config" in /*) runtime_active_config_path=$observed_config ;; esac
fi
if [ -x /jffs/scripts/home-edge-self-heal.sh ]; then
  controller_output=$(HEAL_OBSERVE_ONLY=1 HEAL_LOG_OVERRIDE=/dev/null sh /jffs/scripts/home-edge-self-heal.sh 2>/dev/null || true)
  controller_value() { printf "%s\n" "$controller_output" | sed -n "s/^$1=//p" | head -n 1; }
  controller_state=$(controller_value controller_state)
  controller_auth_state=$(controller_value controller_auth_state)
  controller_observation_state=$(controller_value controller_observation_state)
  controller_dashboard_config_state=$(controller_value dashboard_config_state)
  [ -n "$controller_state" ] || controller_state="unknown"
  [ -n "$controller_auth_state" ] || controller_auth_state="unknown"
  [ -n "$controller_observation_state" ] || controller_observation_state="unknown"
  if [ "$controller_observation_state" = "ready" ]; then
    api_reachable=1
    api_url=$(cat /tmp/self-heal.api 2>/dev/null || true)
    api_version="authenticated"
  fi
fi
self_heal_registration_state="missing"
self_heal_boot_hook_state="missing"
self_heal_policy_mode="unknown"
lifecycle_reconciler_state="absent"
if [ -x /jffs/scripts/home-edge-reconcile-self-heal.sh ]; then
  lifecycle_reconciler_state="present"
  lifecycle_output=$(sh /jffs/scripts/home-edge-reconcile-self-heal.sh --status 2>/dev/null || true)
  lifecycle_value() { printf "%s\n" "$lifecycle_output" | sed -n "s/^$1=//p" | head -n 1; }
  self_heal_registration_state=$(lifecycle_value self_heal_registration_state)
  self_heal_boot_hook_state=$(lifecycle_value self_heal_boot_hook_state)
  self_heal_policy_mode=$(lifecycle_value self_heal_policy_mode)
  [ -n "$self_heal_registration_state" ] || self_heal_registration_state="unknown"
  [ -n "$self_heal_boot_hook_state" ] || self_heal_boot_hook_state="unknown"
  [ -n "$self_heal_policy_mode" ] || self_heal_policy_mode="unknown"
fi
if [ "$api_reachable" != "1" ] && [ "$controller_state" = "unknown" ] && discover_api; then
  api_reachable=1
  controller_state="reachable"
  controller_auth_state="not_required"
  controller_observation_state="ready"
  proxy_state="api_reachable"
fi
if [ "$api_reachable" = "1" ]; then
  proxy_state="api_reachable"
fi
verification_output=""
if [ "$api_reachable" = "1" ] && [ -s /jffs/scripts/home-edge-self-heal.sh ]; then
  verification_output=$(HEAL_VERIFY_ONLY=1 HEAL_LOG_OVERRIDE=/dev/null sh /jffs/scripts/home-edge-self-heal.sh 2>/dev/null || true)
fi
if printf "%s\n" "$verification_output" | grep -q "^verification_state=pass$"; then
  proxy_state="verified"
fi
case "$self_heal_policy_mode" in live) cron_dry_run=0 ;; dry_run) cron_dry_run=1 ;; *) cron_dry_run=unknown ;; esac
print_kv "proxy_state" "$proxy_state"
if [ "$controller_observation_state" = "ready" ]; then
  runtime_state="running"
elif [ "$controller_state" = "reachable" ]; then
  runtime_state="authentication_blocked"
elif [ "$controller_state" = "unreachable" ]; then
  runtime_state="controller_unreachable"
else
  runtime_state="unknown"
fi
print_kv "runtime_state" "$runtime_state"
print_kv "runtime_process_state" "$runtime_process_state"
print_kv "runtime_active_config_path" "$runtime_active_config_path"
print_kv "controller_state" "$controller_state"
print_kv "controller_auth_state" "$controller_auth_state"
print_kv "controller_observation_state" "$controller_observation_state"
[ "$cron_installed" = "1" ] && print_kv "self_heal_cron" "installed" || print_kv "self_heal_cron" "absent"
print_kv "self_heal_registration_state" "$self_heal_registration_state"
print_kv "self_heal_boot_hook_state" "$self_heal_boot_hook_state"
print_kv "lifecycle_reconciler_state" "$lifecycle_reconciler_state"
print_kv "self_heal_policy_mode" "$self_heal_policy_mode"
print_kv "self_heal_cron_dry_run" "$cron_dry_run"
[ -n "${api_url:-}" ] && print_kv "mihomo_api" "$api_url"
[ -n "${api_version:-}" ] && print_kv "mihomo_version" "$api_version"
printf "%s\n" "$cron_list" | grep "home_edge_selfheal" || true
tail -n 8 /tmp/self-heal.log 2>/dev/null || true
echo
echo "## Subscription"
sub_file=/jffs/home-edge-bootstrap/SUBSCRIPTION.local
sub_cache=/jffs/home-edge-bootstrap/cache/subscription.yaml
subscription_state="missing"
subscription_consumption_state="not_observed"
if [ -s "$sub_file" ]; then
  subscription_state="credential_stored"
  print_kv "subscription_file" "present"
  print_kv "subscription_file_bytes" "$(wc -c < "$sub_file")"
else
  print_kv "subscription_file" "missing"
fi
if [ -s "$sub_cache" ]; then
  subscription_state="cache_ready"
  subscription_consumption_state="cache_only_unverified"
  print_kv "subscription_cache" "present"
  print_kv "subscription_cache_bytes" "$(wc -c < "$sub_cache")"
else
  print_kv "subscription_cache" "missing"
fi
if [ "$subscription_state" = "missing" ] && [ "$proxy_state" = "verified" ]; then
  subscription_state="runtime_imported"
  subscription_consumption_state="manual_runtime_import_unverified"
fi
subscription_apply_path=$(SUBSCRIPTION_APPLY_PATH=""; for f in /jffs/scripts/home-edge-policy.env /jffs/scripts/home-edge-policy.local; do [ ! -r "$f" ] || . "$f"; done; printf "%s" "${SUBSCRIPTION_APPLY_PATH:-}")
subscription_runtime_evidence=$(SUBSCRIPTION_RUNTIME_EVIDENCE="/tmp/home-edge-subscription-runtime.evidence"; for f in /jffs/scripts/home-edge-policy.env /jffs/scripts/home-edge-policy.local; do [ ! -r "$f" ] || . "$f"; done; printf "%s" "${SUBSCRIPTION_RUNTIME_EVIDENCE:-/tmp/home-edge-subscription-runtime.evidence}")
subscription_runtime_evidence_max_age=$(SUBSCRIPTION_RUNTIME_EVIDENCE_MAX_AGE_SEC=300; for f in /jffs/scripts/home-edge-policy.env /jffs/scripts/home-edge-policy.local; do [ ! -r "$f" ] || . "$f"; done; printf "%s" "${SUBSCRIPTION_RUNTIME_EVIDENCE_MAX_AGE_SEC:-300}")
if [ -s "$sub_cache" ] && [ -n "$subscription_apply_path" ]; then
  if [ ! -s "$subscription_apply_path" ]; then
    subscription_consumption_state="live_profile_missing"
  elif ! has_cmd cmp; then
    subscription_consumption_state="live_profile_comparison_unavailable"
  elif [ "$sub_cache" = "$subscription_apply_path" ]; then
    subscription_consumption_state="cache_apply_path_alias"
  elif cmp -s "$sub_cache" "$subscription_apply_path" 2>/dev/null; then
    subscription_consumption_state="profile_file_matches_cache"
    if [ -x "$runtime_evidence_helper" ] && [ "$runtime_active_config_path" = "$subscription_apply_path" ] &&
      [ "$controller_observation_state" = "ready" ] && printf "%s\n" "$verification_output" | grep -q "^verification_state=pass$"; then
      evidence_result=$(HOME_EDGE_SUB_CACHE="$sub_cache" HOME_EDGE_SUB_APPLY_PATH="$subscription_apply_path" \
        HOME_EDGE_SUB_EVIDENCE="$subscription_runtime_evidence" HOME_EDGE_RUNTIME_PROCESS_IDENTITY="$runtime_process_identity" \
        HOME_EDGE_RUNTIME_PROCESS_START_EPOCH="$runtime_process_start_epoch" HOME_EDGE_EVIDENCE_MAX_AGE_SEC="$subscription_runtime_evidence_max_age" \
        sh "$runtime_evidence_helper" classify 2>/dev/null || true)
      classified_state=$(printf "%s\n" "$evidence_result" | sed -n "s/^subscription_consumption_state=//p" | head -n 1)
      [ -n "$classified_state" ] && subscription_consumption_state=$classified_state
    fi
  else
    subscription_consumption_state="live_profile_differs_from_cache"
  fi
fi
print_kv "subscription_state" "$subscription_state"
print_kv "subscription_consumption_state" "$subscription_consumption_state"

dashboard_config_state="${controller_dashboard_config_state:-unknown}"
for runtime_config in /etc/ShellClash/config.yaml /etc/ShellClash/config.yml /jffs/ShellClash/config.yaml /jffs/ShellCrash/config.yaml /jffs/ShellCrash/config.yml /jffs/ShellCrash/yamls/config.yaml /jffs/ShellCrash/yamls/config.yml /jffs/shellclash/config.yaml /tmp/ShellClash/config.yaml /tmp/shellclash/config.yaml /etc/clash/config.yaml /tmp/clash/config.yaml /jffs/clash/config.yaml; do
  if [ -r "$runtime_config" ] && grep -Eq '^[[:space:]]*external-ui[[:space:]]*:[[:space:]]*[^#[:space:]]' "$runtime_config"; then
    dashboard_config_state="configured"
    break
  fi
done
print_kv "dashboard_config_state" "$dashboard_config_state"
print_kv "dashboard_reachability_state" "unverified"
echo
echo "## Baseline State"
baseline_state="reviewed"
if [ "$risk_count" -gt 0 ]; then
  baseline_state="risky"
elif [ "$review_count" -gt 0 ]; then
  baseline_state="needs_review"
elif [ "$monitor_count" -gt 0 ]; then
  baseline_state="reviewed_with_monitoring"
fi
print_kv "baseline_state" "$baseline_state"
print_kv "risk_count" "$risk_count"
print_kv "review_count" "$review_count"
print_kv "monitor_count" "$monitor_count"
automation_state="audit_only"
if [ "$admin_state" = "jffs_scripts_ready" ] && [ "$risk_count" -eq 0 ] && [ "$review_count" -eq 0 ]; then
  automation_state="apply_ready"
  [ "$proxy_state" != "absent" ] && automation_state="dry_run_ready"
  if [ "$proxy_state" = "verified" ] && [ "$runtime_process_state" = "running" ] && [ "$self_heal_registration_state" = "ready" ] &&
     [ "$self_heal_boot_hook_state" = "ready" ] && [ "$cron_dry_run" = "0" ]; then
    automation_state="live_managed"
  fi
fi
print_kv "automation_state" "$automation_state"
echo
echo "## Next Safe Action"
if [ "$admin_state" != "jffs_scripts_ready" ]; then
  echo "Enable JFFS custom scripts/configs, then rerun this audit."
elif [ "$risk_count" -gt 0 ]; then
  echo "Resolve ACTION findings or explicitly accept them, then rerun this audit."
elif [ "$review_count" -gt 0 ]; then
  echo "Review REVIEW findings, decide the intended policy, then rerun this audit."
elif [ "$automation_state" = "live_managed" ]; then
  echo "Router baseline and proxy path are live-managed; continue monitoring UPnP or other MONITOR items."
elif [ "$proxy_state" = "absent" ]; then
  echo "Run deploy plan/apply after confirming ShellCrash/Mihomo installation strategy."
elif [ "$proxy_state" != "verified" ]; then
  echo "Import/start the provider profile, verify Mihomo API, then run self-heal dry-run."
else
  echo "Router baseline and proxy path are usable; enable live self-heal only after DRY-RUN logs look correct."
fi'

printf '%s\n' "Router baseline audit log: $log_path"
# shellcheck disable=SC2086
if printf '%s' "$remote_script" | ssh $ssh_opts -- "$router" 'sh -s' >"$log_path" 2>&1; then
  if grep -q '^device_state=' "$log_path"; then
    cat "$log_path"
    exit 0
  fi
  cat "$log_path" 2>/dev/null || true
  echo "ERROR: audit command completed but no machine-readable state was found" >&2
  exit 1
fi
status=$?
cat "$log_path" 2>/dev/null || true
exit "$status"
