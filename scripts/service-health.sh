#!/bin/sh
# One-shot service health; scheduling reuses the existing self-heal lifecycle.
# Generic control logic is in the static bridge; router bypass is an adapter.
set -eu
umask 077
action=${1:---check}
case "$action" in
  --help|-h)
    echo 'usage: sh service-health.sh [--check|--run|--scheduled|--status|--status-env]'
    echo '--check observes only; --run needs an explicitly configured auto mode.'
    exit 0 ;;
  --check|--run|--scheduled|--status|--status-env) ;;
  *) echo 'service_health_state=invalid_action' >&2; exit 2 ;;
esac
here=$(CDPATH= cd "$(dirname "$0")" && pwd)
policy=${SERVICE_HEALTH_POLICY_FILE:-$here/home-edge-policy.env}
if [ -f "$policy" ] && [ ! -L "$policy" ]; then . "$policy"; fi
state_root=${HOME_EDGE_STATE_ROOT:-/jffs/home-edge-bootstrap-state}
config=${HOME_EDGE_SERVICE_HEALTH_CONFIG:-$state_root/service-health.json}
state_dir=${HOME_EDGE_SERVICE_HEALTH_STATE_DIR:-/tmp/home-edge-service-health}
report="$state_dir/report.json"
bridge=${HOME_EDGE_YAMLBRIDGE_BIN:-}
JQ_BIN=${JQ_BIN:-/tmp/home-edge-jq}
[ -x "$JQ_BIN" ] || JQ_BIN=$(which jq 2>/dev/null || true)
secure_helper=${HOME_EDGE_SECURE_TEMP_HELPER:-$here/home-edge-secure-temp.sh}
preflight=${HOME_EDGE_SERVICE_HEALTH_PREFLIGHT:-$here/home-edge-service-health-preflight.sh}
case "$state_dir" in /tmp/?*) ;; *) echo 'service_health_state=unsafe_state_path' >&2; exit 1 ;; esac
case "$state_dir" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.|*//*) exit 1 ;; esac
[ ! -L "$state_dir" ] || exit 1
if [ "$action" = --status-env ]; then
  summary=not_observed
  if [ ! -f "$config" ]; then summary=not_configured
  elif [ -f "$report" ] && [ ! -L "$report" ] && [ -n "$JQ_BIN" ]; then
    summary=$("$JQ_BIN" -r --argjson now "$(date +%s)" '
      if (.observed_at|type)!="number" or .observed_at > $now or $now-.observed_at > 1800 then "stale"
      elif any(.services[]?; .pending==true or (.state|startswith("pending")) or .probe_state=="region_denied" or .probe_state=="transport_failed" or .state=="registration_invalid" or .state=="ownership_unverified") then "needs_attention"
      elif (.services|length)>0 and all(.services[]; .probe_state=="frontend_available") then "frontend_available"
      else "unknown" end' "$report" 2>/dev/null) || summary=unknown
  fi
  case "$summary" in not_configured|not_observed|frontend_available|needs_attention|unknown|stale) ;; *) summary=unknown ;; esac
  printf 'service_health_state=%s\nservice_health_scope=frontend_only\n' "$summary"
  exit 0
fi
if [ "$action" = --status ]; then
  if [ -f "$report" ] && [ ! -L "$report" ] && [ -n "$JQ_BIN" ]; then
    "$JQ_BIN" '{schema_version,observed_at,mode,verification_scope,services}' "$report"
  else echo 'service_health_state=not_observed'; fi
  exit 0
fi
if [ ! -f "$config" ]; then echo 'service_health_state=not_configured'; exit 0; fi
if [ -z "$bridge" ] && [ -f "$here/home-edge-subscription-tools.sh" ] && [ ! -L "$here/home-edge-subscription-tools.sh" ]; then
  bridge=$(sh "$here/home-edge-subscription-tools.sh") || exit 1
fi
[ ! -L "$config" ] && [ -x "$bridge" ] && [ -n "$JQ_BIN" ] && [ -r "$secure_helper" ] || {
  echo 'service_health_state=missing_or_unsafe_prerequisite' >&2; exit 1;
}
. "$secure_helper"
mkdir -p "$state_dir"
chmod 700 "$state_dir"
stage=$(home_edge_secure_temp -d /tmp/home-edge-service-run.XXXXXX) || exit 1
lock=${HOME_EDGE_WRITE_LOCK_DIR:-/tmp/home-edge-bootstrap-write.lock}
owned_lock=0
lock_token=${stage##*/}.$$
bridge_pid=
cleanup() {
  if [ -n "$bridge_pid" ]; then
    kill -TERM "$bridge_pid" 2>/dev/null || true
    wait "$bridge_pid" 2>/dev/null || true
    bridge_pid=
  fi
  rm -rf "$stage"
  if [ "$owned_lock" = 1 ] && [ ! -L "$lock" ] &&
     [ "$(cat "$lock/service-health.owner" 2>/dev/null || true)" = "$lock_token" ] &&
     [ "$(cat "$lock/pid" 2>/dev/null || true)" = "$$" ] &&
     [ "$(cat "$lock/operation" 2>/dev/null || true)" = service-health ]; then
    rm -f "$lock/pid" "$lock/operation" "$lock/started_at" "$lock/service-health.owner"
    rmdir "$lock" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
"$bridge" service-health-validate "$config" "$stage/validated.json" || {
  echo 'service_health_state=invalid_registration_or_outdated_tools' >&2; exit 1;
}
validated=$stage/validated.json
mode=$("$JQ_BIN" -r '.mode // "observe"' "$validated")
case "$mode" in observe|auto) ;; *) echo 'service_health_state=invalid_mode'; exit 1 ;; esac
[ "$action" != --check ] || mode=observe
if [ "$action" = --scheduled ]; then
  [ "$mode" = auto ] || { echo 'service_health_state=observe_not_scheduled'; exit 0; }
  interval=${SERVICE_HEALTH_INTERVAL_SEC:-600}
  case "$interval" in ''|*[!0-9]*) interval=600 ;; esac
  [ "$interval" -ge 180 ] && [ "$interval" -le 86400 ] || interval=600
  now=$(date +%s)
  last=$(cat "$state_dir/last-run" 2>/dev/null || echo 0)
  case "$last:$now" in *[!0-9:]*|:*|*:) echo 'service_health_state=clock_unknown'; exit 0 ;; esac
  if [ "$now" -lt "$last" ]; then echo 'service_health_state=clock_rollback'; exit 0; fi
  [ "$((now - last))" -ge "$interval" ] || { echo 'service_health_state=not_due'; exit 0; }
fi
if [ "$mode" = auto ]; then
  case "$lock" in /tmp/?*) ;; *) exit 1 ;; esac
  case "$lock" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.|*//*) exit 1 ;; esac
  [ ! -L "$lock" ] || exit 1
  if ! mkdir "$lock" 2>/dev/null; then
    echo 'service_health_state=writer_busy'
    echo 'next_step=inspect lock owner; stop writers and verify ownership before recovering a stale service-health lock'
    exit 0
  fi
  owned_lock=1
  printf '%s\n' "$lock_token" >"$lock/service-health.owner"
  printf '%s\n' "$$" >"$lock/pid"
  printf '%s\n' service-health >"$lock/operation"
  date +%s >"$lock/started_at"
fi
runtime_config=$("$JQ_BIN" -r '.runtime_config // empty' "$validated")
# An unverified bypass yields unknown in the backend, never a repair.
unset HOME_EDGE_SERVICE_PROBE_BYPASS_MARK HOME_EDGE_SERVICE_PROBE_IPV6_BYPASS
if [ -f "$preflight" ] && [ ! -L "$preflight" ]; then
  . "$preflight"
  home_edge_service_probe_preflight "$runtime_config" "$bridge" "$stage" || true
fi
core_path=$("$JQ_BIN" -r '.core_path // empty' "$validated")
pid_file=${SERVICE_HEALTH_PID_FILE:-/tmp/ShellCrash/shellcrash.pid}
if [ -f "$pid_file" ] && [ ! -L "$pid_file" ]; then
  core_pid=$(cat "$pid_file")
  case "$core_pid" in ''|*[!0-9]*|0) exit 1 ;; esac
  [ -x "/proc/$core_pid/exe" ] || exit 1
  core_path="/proc/$core_pid/exe"
fi
# Preserve the configured durable transaction journal. Only reports/staging live
# in /tmp; an unconfirmed PUT must remain addressable across a router reboot.
"$JQ_BIN" --arg mode "$mode" --arg core "$core_path" '.mode=$mode | .core_path=$core' "$validated" >"$stage/request.json"
if [ "$owned_lock" = 1 ]; then
  [ ! -L "$lock" ] && [ "$(cat "$lock/service-health.owner" 2>/dev/null || true)" = "$lock_token" ] || exit 1
  export HOME_EDGE_SERVICE_GLOBAL_LOCK="$lock"
  export HOME_EDGE_SERVICE_GLOBAL_TOKEN="$lock_token"
  export HOME_EDGE_SERVICE_GLOBAL_PID="$$"
else
  unset HOME_EDGE_SERVICE_GLOBAL_LOCK HOME_EDGE_SERVICE_GLOBAL_TOKEN HOME_EDGE_SERVICE_GLOBAL_PID
fi
"$bridge" service-health "$stage/request.json" "$stage/report.json" &
bridge_pid=$!
bridge_status=0
wait "$bridge_pid" || bridge_status=$?
bridge_pid=
[ "$bridge_status" = 0 ] || exit "$bridge_status"
[ ! -L "$report" ] || exit 1
mv "$stage/report.json" "$report"
chmod 600 "$report"
if [ "$action" = --scheduled ]; then
  date +%s >"$stage/last-run"
  mv "$stage/last-run" "$state_dir/last-run"
fi
"$JQ_BIN" '{schema_version,observed_at,mode,verification_scope,services}' "$report"
