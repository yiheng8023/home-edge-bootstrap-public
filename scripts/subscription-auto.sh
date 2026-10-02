#!/bin/sh
# One guarded node-update entrypoint for periodic, demand and manual requests.
set -eu
umask 077
here=$(CDPATH= cd "$(dirname "$0")" && pwd)
policy=${SUBSCRIPTION_POLICY_FILE:-/jffs/scripts/home-edge-policy.env}
if [ -r "$policy" ]; then . "$policy"; fi
state=${HOME_EDGE_STATE_ROOT:-/jffs/home-edge-bootstrap-state}
[ ! -r "$state/policy.local" ] || . "$state/policy.local"
enabled=${SUBSCRIPTION_AUTO_ENABLED:-0}
interval=${SUBSCRIPTION_AUTO_INTERVAL_SEC:-86400}
cooldown=${SUBSCRIPTION_AUTO_COOLDOWN_SEC:-3600}
checks=${SUBSCRIPTION_AUTO_FAILURE_CHECKS:-3}
drop=${SUBSCRIPTION_AUTO_HEALTH_PERCENT:-50}
source_profile=${SUBSCRIPTION_SOURCE_PROFILE:-/jffs/ShellCrash/yamls/config.yaml}
live_profile=${SUBSCRIPTION_LIVE_PROFILE:-/tmp/ShellCrash/config.yaml}
source_file=${SUBSCRIPTION_FILE:-$state/SUBSCRIPTION.local}
filters=${SUBSCRIPTION_GROUP_FILTERS_FILE:-$state/subscription-groups.json}
secret_file=${CLASH_SECRET_FILE:-$state/CONTROLLER_SECRET.local}
data_dir=${HOME_EDGE_SHELLCRASH_DIR:-/jffs/ShellCrash}
native_port=$(sed -n 's/^db_port=//p' "$data_dir/configs/ShellCrash.cfg" 2>/dev/null | head -1 || true)
native_port=${native_port#\"}; native_port=${native_port%\"}
native_port=${native_port#\'}; native_port=${native_port%\'}
case "$native_port" in ''|*[!0-9]*) native_port="";; esac
api=${SUBSCRIPTION_API:-http://127.0.0.1:${native_port:-9999}}
canary_api=${SUBSCRIPTION_CANARY_API:-http://127.0.0.1:19999}
probe=${SUBSCRIPTION_AUTO_PROBE_URL:-http://www.gstatic.com/generate_204}
uplink_probe=${SUBSCRIPTION_UPLINK_PROBE_URL:-https://example.com}
data_dir=${HOME_EDGE_SHELLCRASH_DIR:-/jffs/ShellCrash}
auto_dir="$state/subscription-auto"
status="$auto_dir/status.json"
transactions="$auto_dir/transactions"
lock=${HOME_EDGE_WRITE_LOCK_DIR:-/tmp/home-edge-bootstrap-write.lock}
work=""
lock_held=0
lock_token=""
canary_pid=""
guard_pid=""
tx=""
committed=0
tx_created=0
recovery_held=""
cache_tmp=""
mode=${1:---tick}
helper() { if [ -r "$here/home-edge-$1" ]; then printf '%s\n' "$here/home-edge-$1"; else printf '%s\n' "$here/$1"; fi; }
merge=$(helper subscription-merge.jq)
tools=$(helper subscription-tools.sh)
self_heal=${SUBSCRIPTION_SELF_HEAL_SCRIPT:-$(helper self-heal.sh)}
curl=${CURL_BIN:-curl}
jq=${JQ_BIN:-jq}
now=${SUBSCRIPTION_TEST_NOW:-$(date +%s)}
say() { printf 'subscription_auto=%s\n' "$1"; }
fail() { say "$1" >&2; exit 1; }
for value in "$interval" "$cooldown" "$checks" "$drop" "$now"; do case "$value" in ''|*[!0-9]*) fail invalid_numeric_policy;; esac; done
[ "$interval" -ge 3600 ] && [ "$cooldown" -ge 60 ] && [ "$checks" -ge 1 ] && [ "$drop" -le 100 ] || fail invalid_policy_range
case "$enabled" in 0|1) ;; *) fail invalid_enable_policy;; esac
for path in "$state" "$source_profile" "$live_profile" "$lock"; do
  case "$path" in /*) ;; *) fail absolute_path_required;; esac
  case "$path" in /|*'/../'*|*'/..'|*'/./'*|*'/.'|*'//'*) fail unsafe_path;; esac
done
no_links() {
  checked=""
  saved_ifs=$IFS; IFS='/'; set -f
  for part in $1; do
    [ -n "$part" ] || continue
    checked="$checked/$part"
    [ ! -L "$checked" ] || { IFS=$saved_ifs; set +f; fail symbolic_link_boundary; }
  done
  IFS=$saved_ifs; set +f
}
validate_effect_paths=1
case "$mode:$enabled" in
  --reconcile:0) validate_effect_paths=0;;
  --boot:0) [ -d "$transactions" ] || validate_effect_paths=0;;
esac
if [ "$validate_effect_paths" = 1 ]; then
  for path in "$state" "$source_profile" "$live_profile" "$lock" "$filters" "$source_file" "$secret_file"; do no_links "$path"; done
fi
case "$api:$canary_api" in http://127.0.0.1:*:http://127.0.0.1:*) ;; *) fail loopback_controller_required;; esac
sha() { openssl dgst -sha256 "$1" | awk '{print $NF}'; }
input_stamp() {
  for input in "$policy" "$state/policy.local" "$source_file" "$filters" "$secret_file"; do
    if [ -f "$input" ] && [ ! -L "$input" ]; then sha "$input"; else printf 'absent\n'; fi
  done
}
birth() { sed 's/^.*) //' "/proc/$1/stat" | awk '{print $20}'; }
core_running() {
  core_state=$(sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $1}')
  case "$core_state" in ''|Z|X) return 1;; esac
  kill -0 "$1" 2>/dev/null
}
boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)
lease_valid() { [ -n "$lock_token" ] && [ "$(cat "$lock/operation" 2>/dev/null || true)" = "$lock_token" ]; }
release_lock() {
  if lease_valid; then rm -f "$lock/pid" "$lock/operation" "$lock/started_at"; rmdir "$lock" 2>/dev/null || true; fi
  lock_held=0
}
recovery_release() {
  if [ -n "$recovery_held" ] && [ "$(cat "$recovery_held/owner" 2>/dev/null || true)" = "$$:$(birth $$):$boot_id" ]; then
    rm -f "$recovery_held/owner"; rmdir "$recovery_held"
  fi
  recovery_held=""
}
recovery_acquire() {
  # The mutex is RAM-only; journal/backups are persistent. A reboot cannot strand it.
  mutex="/tmp/home-edge-subscription-recovery.${1##*/}.lock"
  for n in 1 2 3 4 5; do
    if mkdir "$mutex" 2>/dev/null; then
      recovery_held="$mutex"; printf '%s\n' "$$:$(birth $$):$boot_id" >"$mutex/owner"; return 0
    fi
    mutex_owner=$(cat "$mutex/owner" 2>/dev/null || true)
    mutex_pid=${mutex_owner%%:*}
    case "$mutex_pid" in ''|*[!0-9]*) fail unknown_recovery_owner;; esac
    mutex_rest=${mutex_owner#*:}; mutex_birth=${mutex_rest%%:*}; mutex_boot=${mutex_rest#*:}
    if [ "$mutex_boot" != "$boot_id" ] || [ "$(birth "$mutex_pid" 2>/dev/null || true)" != "$mutex_birth" ]; then
      [ "$(cat "$mutex/owner" 2>/dev/null || true)" = "$mutex_owner" ] || continue
      rm -f "$mutex/owner"; rmdir "$mutex" || fail recovery_owner_changed
    else sleep 1; fi
  done
  fail recovery_already_active
}
load_status() {
  if [ -s "$status" ]; then "$jq" -e 'type=="object"' "$status" >/dev/null || fail invalid_status;
  else printf '%s\n' '{"last_success":0,"last_attempt":0,"backoff_until":0,"failures":0,"health_failures":0,"health_baseline":0,"provider_interval":0,"last_result":"never"}' >"$status"; fi
}
write_status() {
  updated_status=$("$jq" "$@" "$status")
  if [ "$updated_status" != "$(cat "$status")" ]; then
    printf '%s\n' "$updated_status" >"$status.tmp.$$"; mv "$status.tmp.$$" "$status"
  fi
}
authorize() {
  [ -s "$secret_file" ] || fail controller_secret_missing
  secret=$(cat "$secret_file")
  case "$secret" in *[!A-Za-z0-9_-]*|'') fail unsupported_secret_encoding;; esac
  printf 'header = "Authorization: Bearer %s"\n' "$secret" >"$work/auth.conf"
}
capi() { "$curl" --config "$work/auth.conf" --noproxy '*' --connect-timeout 2 --max-time 10 -fsS "$@"; }
reload_runtime() {
  # Omitted path reloads the already-bound CLI config; no safe-path bypass or force.
  capi -X PUT -H 'Content-Type: application/json' --data '{}' -o "$work/reload-response" -w '%{http_code}' "$api/configs" >"$work/reload-http"
  [ "$(cat "$work/reload-http")" = 204 ]
}
restore_selections() {
  target=$1
  endpoint=${2:-$api}
  "$jq" -r 'to_entries[] | [.key,.value] | @base64' "$target" | while IFS= read -r item; do
    decoded=$(printf '%s' "$item" | base64 -d)
    group=$(printf '%s' "$decoded" | "$jq" -r '.[0]|@uri')
    body=$(printf '%s' "$decoded" | "$jq" -c '{name:.[1]}')
    printf '%s' "$body" | capi -X PUT -H 'Content-Type: application/json' --data-binary @- "$endpoint/proxies/$group" >/dev/null
  done
}
recover() {
  dir=$1
  case "$dir" in "$transactions"/tx-[0-9]*-[0-9]*) ;; *) fail unsafe_transaction_path;; esac
  [ -d "$dir" ] && [ ! -L "$dir" ] || fail unsafe_transaction_directory
  [ -f "$dir/accepted" ] && return 0
  [ -s "$dir/journal.json" ] || fail missing_journal
  [ ! -f "$dir/selection-conflict" ] || fail rollback_selection_conflict
  [ ! -f "$dir/rolled-back" ] || return 0
  recovery_acquire "$dir"
  [ ! -f "$dir/accepted" ] && [ ! -f "$dir/rolled-back" ] || { recovery_release; return 0; }
  lease_valid || fail writer_lease_lost
  # Only compensate this transaction's old/new bytes; never overwrite another actor.
  old_source=$("$jq" -r .old_source "$dir/journal.json")
  new_source=$("$jq" -r .new_source "$dir/journal.json")
  current=$(sha "$source_profile")
  if [ "$current" != "$old_source" ] && [ "$current" != "$new_source" ]; then fail concurrent_source_change; fi
  if [ "${2:-}" != boot ]; then
    bound_pid=$("$jq" -r .pid "$dir/journal.json")
    core_running "$bound_pid" && [ "$(birth "$bound_pid" 2>/dev/null || true)" = "$("$jq" -r .birth "$dir/journal.json")" ] || fail rollback_process_changed
    old_live=$("$jq" -r .old_live "$dir/journal.json"); new_live=$("$jq" -r .new_live "$dir/journal.json")
    current=$(sha "$live_profile")
    if [ "$current" != "$old_live" ] && [ "$current" != "$new_live" ]; then fail concurrent_runtime_change; fi
    capi "$api/proxies" >"$work/rollback-current.json" || fail rollback_controller_unavailable
    # A choice valid only in the new membership must not be silently lost on rollback.
    "$jq" -ne --slurpfile old "$dir/runtime-before.json" --slurpfile current "$work/rollback-current.json" '
      $current[0].proxies|to_entries|all(. as $e|if .value.type=="Selector" then
        if .key=="GLOBAL" and ($old[0]["proxy-groups"]|map(.name)|index("GLOBAL")|not) then (($old[0].proxies|map(.name))+($old[0]["proxy-groups"]|map(.name))+["DIRECT","REJECT"]|index($e.value.now))
        else ($old[0]["proxy-groups"]|map(select(.name==$e.key))|.[0].proxies|index($e.value.now)) end
      else true end)' >/dev/null || { touch "$dir/selection-conflict"; fail rollback_selection_conflict; }
  fi
  cp "$dir/source-before.yaml" "$source_profile.recovery"; chmod 600 "$source_profile.recovery"; mv "$source_profile.recovery" "$source_profile"
  if [ "${2:-}" != boot ]; then
    cp "$dir/runtime-before.yaml" "$live_profile.recovery"; chmod 600 "$live_profile.recovery"; mv "$live_profile.recovery" "$live_profile"
    pid=$("$jq" -r .pid "$dir/journal.json")
    reload_runtime || fail rollback_reload_failed
    # The core's store-selected cache restores current choices; never replay an old PUT.
    if [ -x "$data_dir/task/task.sh" ]; then "$data_dir/task/task.sh" web_save_auto >"$work/rollback-save.log" 2>&1 || fail rollback_save_failed; fi
  fi
  touch "$dir/rolled-back"
  recovery_release
  say rolled_back
}
cleanup() {
  rc=$?
  trap - EXIT HUP INT TERM
  recovery_release || true
  if lease_valid && [ -n "$tx" ] && [ "$committed" = 1 ] && [ ! -f "$tx/accepted" ] && [ ! -f "$tx/rolled-back" ]; then
    (trap recovery_release EXIT; recover "$tx") || rc=1
  fi
  if [ -n "$guard_pid" ]; then
    # The guard records its sleep child so no orphan allocation survives completion.
    if [ -n "$tx" ] && [ -s "$tx/sleep.pid" ]; then kill "$(cat "$tx/sleep.pid")" 2>/dev/null || true; fi
    kill "$guard_pid" 2>/dev/null || true
    wait "$guard_pid" 2>/dev/null || true
  fi
  if [ -n "$canary_pid" ]; then kill "$canary_pid" 2>/dev/null || true; wait "$canary_pid" 2>/dev/null || true; fi
  if [ "$tx_created" = 1 ] && [ "$committed" = 0 ]; then
    case "$tx" in "$transactions/tx-$now-$$") [ -L "$tx" ] || rm -rf "$tx";; esac
  fi
  if [ -n "$work" ] && [ -d "$work" ]; then
    case "$work" in /tmp/home-edge-subscription.*) rm -rf "$work";; esac
  fi
  [ -z "$cache_tmp" ] || rm -f "$cache_tmp"
  rm -f "$status.tmp.$$" 2>/dev/null || true
  if [ "$lock_held" = 1 ]; then release_lock; fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
acquire() {
  if ! mkdir "$lock" 2>/dev/null; then
    owner=$(cat "$lock/pid" 2>/dev/null || true)
    case "$owner" in ''|*[!0-9]*) fail busy;; esac
    # Unknown ownership is preserved, never recovered merely because a timeout elapsed.
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null && [ -f "$lock/operation" ]; then
      rm -f "$lock/pid" "$lock/operation" "$lock/started_at"; rmdir "$lock"; mkdir "$lock" || fail busy
    else fail busy; fi
  fi
  lock_held=1
  lock_token="subscription-auto.$$.$(birth $$)"
  echo $$ >"$lock/pid"; echo "$lock_token" >"$lock/operation"; echo "$now" >"$lock/started_at"
}
case "$mode" in
  --status) [ -s "$status" ] && cat "$status" || say not_initialized; exit 0;;
  --reconcile|--boot)
    if [ "$mode" = --boot ] && [ -d "$transactions" ]; then
      acquire
      for pending in "$transactions"/tx-*; do
        [ -d "$pending" ] || continue
        if [ ! -f "$pending/accepted" ] && [ ! -f "$pending/rolled-back" ]; then recover "$pending" boot; fi
      done
    fi
    if [ "$enabled" = 1 ]; then
      [ -s "$state/runtime/yamlbridge.gz" ] && [ -s "$filters" ] && [ -s "$source_file" ] || fail auto_prerequisites_missing
      cru d home_edge_subscription 2>/dev/null || true
      cru a home_edge_subscription '*/5 * * * * sh /jffs/scripts/home-edge-subscription-auto.sh --tick'
      matches=$(cru l | grep -F '#home_edge_subscription#' | wc -l | tr -d ' ')
      [ "$matches" = 1 ] || fail registration_failed
      say registered
    else
      if cru l 2>/dev/null | grep -Fq '#home_edge_subscription#'; then cru d home_edge_subscription; fi
      say disabled
    fi
    exit 0;;
  --guard)
    tx=${2:?transaction required}
    work=${3:?work required}
    lock_held=0
    lock_token=$("$jq" -r .lock_token "$tx/journal.json")
    committed=0
    sleep "${SUBSCRIPTION_TEST_GUARD_SECONDS:-120}" & sleeper=$!; echo "$sleeper" >"$tx/sleep.pid"; wait "$sleeper" || exit 0
    lease_valid || exit 1
    touch "$tx/expired"
    [ -f "$tx/accepted" ] || recover "$tx"
    if [ -s "$status" ] && [ ! -f "$tx/accepted" ]; then
      write_status --argjson b "$((now+cooldown))" '.failures+=1 | .backoff_until=$b | .last_result="guard_timeout"'
    fi
    # Release only this update's writer lock after timeout recovery.
    release_lock
    parent=$("$jq" -r .owner "$tx/journal.json")
    if ! kill -0 "$parent" 2>/dev/null; then
      rm -f "$state/cache/.subscription-auto.$parent"
      case "$work" in /tmp/home-edge-subscription."$parent") rm -rf "$work";; esac
    fi
    work=""; tx=""; exit 0;;
  --check) enabled=1;;
  --tick|--refresh) ;;
  *) fail unsupported_mode;;
esac
[ "$enabled" = 1 ] || { say disabled; exit 0; }
[ "$boot_id" != unknown ] || fail boot_identity_unavailable
mkdir -p "$auto_dir" "$transactions"; chmod 700 "$auto_dir" "$transactions"
acquire
for pending in "$transactions"/tx-*; do
  [ -d "$pending" ] || continue
  if [ ! -f "$pending/accepted" ] && [ ! -f "$pending/rolled-back" ]; then fail pending_transaction_requires_recovery; fi
done
work=/tmp/home-edge-subscription.$$
[ ! -e "$work" ] || fail work_path_exists
mkdir "$work"; chmod 700 "$work"
if [ "$mode" = --check ]; then status="$work/check-status.json"; fi
load_status
authorize
parser=$(sh "$tools") || fail parser_missing
"$parser" decode "$live_profile" "$work/controller-binding.json" || fail invalid_live_profile
controller=$("$jq" -r '."external-controller" // ""' "$work/controller-binding.json")
if [ -z "${SUBSCRIPTION_API:-}" ]; then
  case "$controller" in 127.0.0.1:*|0.0.0.0:*|:*) port=${controller##*:};; *) fail controller_binding_missing;; esac
  case "$port" in ''|*[!0-9]*) fail controller_binding_missing;; esac
  api="http://127.0.0.1:$port"
fi
mixed_port=$("$jq" -r '."mixed-port" // 0' "$work/controller-binding.json")
case "$mixed_port" in ''|*[!0-9]*) fail invalid_proxy_binding;; esac
fetch_fallback=${SUBSCRIPTION_AUTO_PROXY_FALLBACK:-1}
case "$fetch_fallback" in 0|1) ;; *) fail invalid_proxy_fallback_policy;; esac
bound_inputs=$(input_stamp)
capi "$api/proxies" >"$work/proxies.json" || fail controller_unavailable
"$jq" -e '.proxies|type=="object"' "$work/proxies.json" >/dev/null || fail invalid_controller_response
healthy=$("$jq" '[.proxies[]|select((.all|type)!="array" and .type!="Direct" and .type!="Reject" and .type!="Pass" and .type!="PassRule" and .alive==true)]|length' "$work/proxies.json")
baseline=$("$jq" -r .health_baseline "$status")
bad=$("$jq" -r .health_failures "$status")
if [ "$healthy" = 0 ] || { [ "$baseline" -gt 0 ] && [ $((healthy * 100)) -lt $((baseline * drop)) ]; }; then
  [ "$bad" -ge "$checks" ] || bad=$((bad+1))
else bad=0; fi
last_success=$("$jq" -r .last_success "$status")
last_attempt=$("$jq" -r .last_attempt "$status")
backoff=$("$jq" -r .backoff_until "$status")
provider_interval=$("$jq" -r .provider_interval "$status")
[ "$provider_interval" -le "$interval" ] || interval=$provider_interval
# Renew the health reference daily, so a long-obsolete peak does not trigger forever.
if [ $((now-last_success)) -ge 86400 ] || [ "$baseline" = 0 ]; then baseline=$healthy; fi
write_status --argjson n "$bad" --argjson b "$baseline" '.health_failures=$n | .health_baseline=$b'
if [ "$mode" = --tick ]; then
  [ "$now" -ge "$backoff" ] || { say backoff; exit 0; }
  [ $((now-last_attempt)) -ge "$cooldown" ] || { say cooldown; exit 0; }
  if [ $((now-last_success)) -lt "$interval" ] && [ "$bad" -lt "$checks" ]; then say not_due; exit 0; fi
fi
# A bad uplink is not evidence that the subscription needs replacing.
if which nvram >/dev/null 2>&1; then [ "$(nvram get wan0_state_t)" = 2 ] || { say uplink_down; exit 0; }; fi
"$curl" --noproxy '*' --connect-timeout 3 --max-time 8 -fsS -o /dev/null "$uplink_probe" || { say uplink_probe_failed; exit 0; }
write_status --argjson n "$now" '.last_attempt=$n'
attempt_failed() {
  lease_valid || fail "$1"
  failures=$("$jq" -r .failures "$status"); failures=$((failures+1))
  delay=$cooldown; count=1
  while [ "$count" -lt "$failures" ] && [ "$delay" -lt 86400 ]; do delay=$((delay*2)); count=$((count+1)); done
  [ "$delay" -le 86400 ] || delay=86400
  if [ -s "$work/headers" ]; then
    retry_after=$(awk 'tolower($1)=="retry-after:" {gsub("\r","",$2); print $2}' "$work/headers" | tail -1)
    case "$retry_after" in ''|*[!0-9]*) retry_after=0;; esac
    [ ${#retry_after} -le 8 ] || retry_after=0
    [ "$retry_after" -le "$delay" ] || delay=$retry_after
  fi
  write_status --argjson f "$failures" --argjson b "$((now+delay))" --arg r "$1" '.failures=$f | .backoff_until=$b | .last_result=$r'
  fail "$1"
}
parser=$(sh "$tools") || attempt_failed parser_missing
[ -s "$source_file" ] && [ -s "$filters" ] || attempt_failed source_binding_missing
url=$(head -n 1 "$source_file" | tr -d '\r')
case "$url" in https://*) ;; *) attempt_failed https_subscription_required;; esac
fetch_rc=0
"$curl" --noproxy '*' --proto '=https' --proto-redir '=https' --connect-timeout 5 --max-time 30 --max-filesize 10485760 -fsSL -D "$work/headers" -o "$work/subscription.yaml" "$url" 2>"$work/fetch-error" || fetch_rc=$?
if [ "$fetch_rc" != 0 ]; then
  # Transport-only fallback uses the current local core. No converter or TLS downgrade.
  case "$fetch_rc:$fetch_fallback" in 5:1|6:1|7:1|28:1|35:1|56:1)
    [ "$mixed_port" -gt 0 ] || attempt_failed fetch_failed
    rm -f "$work/subscription.yaml" "$work/headers"
    "$curl" --noproxy '' --proxy "http://127.0.0.1:$mixed_port" --proto '=https' --proto-redir '=https' --connect-timeout 5 --max-time 30 --max-filesize 10485760 -fsSL -D "$work/headers" -o "$work/subscription.yaml" "$url" 2>"$work/fetch-error" || attempt_failed fetch_failed
    ;;
    *) attempt_failed fetch_failed;;
  esac
fi
"$parser" decode "$work/subscription.yaml" "$work/subscription.json" || attempt_failed invalid_subscription
[ -f "$source_profile" ] && [ ! -L "$source_profile" ] && [ -f "$live_profile" ] && [ ! -L "$live_profile" ] || attempt_failed unsafe_live_profile
cp "$source_profile" "$work/source-before.yaml"; cp "$live_profile" "$work/runtime-before.yaml"
"$parser" decode "$work/source-before.yaml" "$work/source-before.json"
"$parser" decode "$work/runtime-before.yaml" "$work/runtime-before.json"
"$jq" -S '.proxies|with_entries(select(.value.type=="Selector"))|map_values(.now)' "$work/proxies.json" >"$work/selections.json"
for kind in source runtime; do
  "$jq" -n --slurpfile base "$work/$kind-before.json" --slurpfile subscription "$work/subscription.json" --slurpfile filters "$filters" --slurpfile snapshot "$work/proxies.json" -f "$merge" >"$work/$kind-candidate.json" 2>"$work/merge-error" || attempt_failed policy_or_pin_conflict
done
"$jq" -e '.profile."store-selected"!=false' "$work/runtime-candidate.json" >/dev/null || attempt_failed selection_persistence_required
changed=$("$jq" -n --slurpfile a "$work/source-before.json" --slurpfile b "$work/source-candidate.json" --slurpfile r "$work/runtime-before.json" --slurpfile c "$work/runtime-candidate.json" 'def nodes: {proxies:(.proxies|sort_by(.name)),groups:(.["proxy-groups"]|map({name,proxies:(.proxies|sort)}))}; ($a[0]|nodes)!=($b[0]|nodes) or ($r[0]|nodes)!=($c[0]|nodes)')
[ "$(input_stamp)" = "$bound_inputs" ] || attempt_failed changed_inputs
provider_hours=$(awk 'tolower($1)=="profile-update-interval:" {gsub("\r","",$2); print $2}' "$work/headers" | tail -1)
case "$provider_hours" in ''|*[!0-9]*) provider_seconds=0;; *) provider_seconds=$((provider_hours*3600)); [ "$provider_seconds" -le 7776000 ] || provider_seconds=7776000;; esac
success_status() { write_status --argjson n "$now" --argjson h "$healthy" --argjson p "$provider_seconds" --arg r "$1" '.last_success=$n | .failures=0 | .backoff_until=0 | .health_failures=0 | .health_baseline=$h | .provider_interval=$p | .last_result=$r'; }
mkdir -p "$state/cache"
cache_tmp="$state/cache/.subscription-auto.$$"
cp "$work/subscription.yaml" "$cache_tmp"; chmod 600 "$cache_tmp"
if [ "$changed" = false ]; then
  if [ "$mode" = --check ]; then say unchanged; exit 0; fi
  mv "$state/cache/.subscription-auto.$$" "$state/cache/subscription.yaml"
  cache_tmp=""
  success_status unchanged; say unchanged; exit 0
fi
for kind in source runtime; do "$parser" encode "$work/$kind-candidate.json" "$work/$kind-candidate.yaml"; done
pid=${SUBSCRIPTION_CORE_PID:-$(cat /tmp/ShellCrash/shellcrash.pid 2>/dev/null || true)}
case "$pid" in ''|*[!0-9]*) attempt_failed runtime_pid_missing;; esac
core=${SUBSCRIPTION_CORE_BIN:-/proc/$pid/exe}
[ -x "$core" ] || attempt_failed runtime_binary_missing
core_running "$pid" || attempt_failed runtime_not_running
core_birth=$(birth "$pid")
if [ -z "${SUBSCRIPTION_CORE_BIN:-}" ]; then
  bound_config=$(tr '\000' '\n' <"/proc/$pid/cmdline" | awk 'previous=="-f" || previous=="--config" {print; exit} {previous=$0}')
  [ "$bound_config" = "$live_profile" ] || attempt_failed runtime_identity_mismatch
fi
"$core" -t -d "$data_dir" -f "$work/runtime-candidate.yaml" >"$work/validate.log" 2>&1 || attempt_failed candidate_invalid
# Isolate all listeners and policy routing; only the node transport is tested.
"$jq" --arg api "${canary_api#http://}" '. | del(.listeners,.tunnels,."rule-providers",."external-controller-tls",."external-controller-unix",."external-controller-pipe",."external-ui",."external-ui-url",."external-ui-name") | .port=0 | ."mixed-port"=0 | ."socks-port"=0 | ."redir-port"=0 | ."tproxy-port"=0 | ."allow-lan"=false | ."bind-address"="127.0.0.1" | ."external-controller"=$api | .dns={enable:false} | .tun={enable:false} | .iptables={enable:false} | .ntp={enable:false} | ."tuic-server"={enable:false} | ."ss-config"="" | ."vmess-config"="" | ."tcptun-config"="" | ."udptun-config"="" | ."geo-auto-update"=false | ."log-level"="silent" | ."proxy-groups" += [{name:"CANARY",type:"select",proxies:[.proxies[].name]}] | .rules=["MATCH,CANARY"]' "$work/runtime-candidate.json" >"$work/canary.json"
"$parser" encode "$work/canary.json" "$work/canary.yaml"
if capi "$canary_api/version" >/dev/null 2>&1; then attempt_failed canary_port_in_use; fi
mkdir "$work/canary-data"
"$core" -d "$work/canary-data" -f "$work/canary.yaml" >"$work/canary.log" 2>&1 & canary_pid=$!
ready=0
for n in 1 2 3 4 5 6 7 8 9 10; do if capi "$canary_api/version" >/dev/null 2>&1; then ready=1; break; fi; sleep 1; done
[ "$ready" = 1 ] || attempt_failed canary_start_failed
restore_selections "$work/selections.json" "$canary_api" || attempt_failed canary_choices_failed
"$jq" -r --slurpfile old "$work/proxies.json" '[.proxies[] | .name as $n | {name:$n,rank:(if $old[0].proxies[$n].alive then 0 else 1 end)}] | sort_by(.rank) | .[:6][] | .name | @uri' "$work/runtime-candidate.json" >"$work/samples"
passes=0
while IFS= read -r node; do
  result=$(capi "$canary_api/proxies/$node/delay?url=$(printf '%s' "$probe" | "$jq" -sRr @uri)&timeout=5000" 2>/dev/null || true)
  if printf '%s' "$result" | "$jq" -e '.delay>0' >/dev/null 2>&1; then passes=$((passes+1)); fi
done <"$work/samples"
[ "$passes" -ge 2 ] || attempt_failed canary_health_failed
kill "$canary_pid"; wait "$canary_pid" 2>/dev/null || true; canary_pid=""
if [ "$mode" = --check ]; then say candidate_verified; exit 0; fi
# Refuse publication if another actor changed bytes or user choices during staging.
cmp -s "$source_profile" "$work/source-before.yaml" && cmp -s "$live_profile" "$work/runtime-before.yaml" || attempt_failed concurrent_config_change
[ "$(input_stamp)" = "$bound_inputs" ] || attempt_failed changed_inputs
capi "$api/proxies" >"$work/current.json"
"$jq" -S '.proxies|with_entries(select(.value.type=="Selector"))|map_values(.now)' "$work/current.json" >"$work/current-selections.json"
cmp -s "$work/current-selections.json" "$work/selections.json" || attempt_failed concurrent_selection_change
core_running "$pid" && [ "$(birth "$pid" 2>/dev/null || true)" = "$core_birth" ] || attempt_failed runtime_process_changed
if [ -z "${SUBSCRIPTION_CORE_PID:-}" ]; then
  [ "$(cat /tmp/ShellCrash/shellcrash.pid 2>/dev/null || true)" = "$pid" ] || attempt_failed runtime_process_changed
fi
# Reserve flash for snapshots, staged source/cache bytes and recovery bookkeeping.
count=0
for previous in $(ls -1d "$transactions"/tx-* 2>/dev/null | sort -r); do
  count=$((count+1)); [ "$count" -le 2 ] && continue
  [ -f "$previous/accepted" ] || [ -f "$previous/rolled-back" ] || continue
  [ ! -L "$previous" ] || continue
  rm -rf "$previous"
done
required_bytes=$(wc -c "$work/source-before.yaml" "$work/runtime-before.yaml" "$work/runtime-before.json" "$work/source-candidate.yaml" "$work/subscription.yaml" | awk 'END {print $1}')
available_kib=$(df -Pk "$state" | awk 'END {print $4}')
case "$available_kib" in ''|*[!0-9]*) attempt_failed flash_capacity_unknown;; esac
[ "$available_kib" -ge $(((required_bytes+1023)/1024+2048)) ] || attempt_failed flash_capacity_low
tx="$transactions/tx-$now-$$"; mkdir "$tx"; tx_created=1; chmod 700 "$tx"
cp "$work/source-before.yaml" "$tx/source-before.yaml" && cp "$work/runtime-before.yaml" "$tx/runtime-before.yaml" && cp "$work/selections.json" "$tx/selections.json" && cp "$work/runtime-before.json" "$tx/runtime-before.json" || attempt_failed transaction_backup_failed
[ ! -f "$data_dir/configs/web_save" ] || cp "$data_dir/configs/web_save" "$tx/web-save-before"
"$jq" -n --arg os "$(sha "$source_profile")" --arg ol "$(sha "$live_profile")" --arg ns "$(sha "$work/source-candidate.yaml")" --arg nl "$(sha "$work/runtime-candidate.yaml")" --arg b "$(birth "$pid")" --arg token "$lock_token" --arg boot "$boot_id" --argjson p "$pid" --argjson o "$$" '{old_source:$os,old_live:$ol,new_source:$ns,new_live:$nl,pid:$p,birth:$b,owner:$o,lock_token:$token,boot_id:$boot}' >"$tx/journal.json"
sh "$0" --guard "$tx" "$work" >"$tx/guard.log" 2>&1 & guard_pid=$!
printf '%s\n' "$guard_pid" >"$tx/guard.pid"
printf '%s\n' "$guard_pid" >"$lock/pid"
committed=1
recovery_acquire "$tx"
lease_valid && [ ! -f "$tx/expired" ] || attempt_failed writer_lease_lost
cp "$work/source-candidate.yaml" "$source_profile.new"; cp "$work/runtime-candidate.yaml" "$live_profile.new"
chmod 600 "$source_profile.new" "$live_profile.new"
mv "$source_profile.new" "$source_profile"; mv "$live_profile.new" "$live_profile"
reload_runtime || attempt_failed reload_failed
recovery_release
capi "$api/proxies" >"$work/after.json"
"$jq" -e '.proxies|to_entries|all(. as $e|.value.type!="Selector" or ($e.value.all|index($e.value.now))!=null)' "$work/after.json" >/dev/null || attempt_failed invalid_active_selection
"$jq" -S '.proxies|with_entries(select(.value.type=="Selector"))|map_values(.now)' "$work/after.json" >"$work/after-selections.json"
# Different valid choices can be the user's newer click; do not write stale choices back.
if ! HOME_EDGE_WRITE_LOCK_HELD=1 HEAL_VERIFY_ONLY=1 CLASH_SECRET_FILE="$secret_file" sh "$self_heal" >"$work/route.log" 2>&1; then attempt_failed route_verification_failed; fi
grep -Fq 'verification_state=pass' "$work/route.log" || attempt_failed route_not_verified
if [ -x "$data_dir/task/task.sh" ]; then
  capi "$api/proxies" >"$work/after.json"
  "$data_dir/task/task.sh" web_save_auto >"$work/save.log" 2>&1 || attempt_failed save_failed
  "$jq" '.proxies|with_entries(select(.value.type=="Selector" and .value.now!=.value.all[0]))|map_values(.now)' "$work/after.json" >"$work/expected-saved.json"
  "$jq" -Rn '[inputs|select(length>0)|split(",")|if length==2 then {key:.[0],value:.[1]} else error("unsupported saved selection") end]|from_entries' "$data_dir/configs/web_save" >"$work/actual-saved.json" || attempt_failed save_format_unsupported
  "$jq" -ne --slurpfile expected "$work/expected-saved.json" --slurpfile actual "$work/actual-saved.json" '$expected[0]==$actual[0]' >/dev/null || attempt_failed saved_choices_mismatch
fi
recovery_acquire "$tx"
lease_valid && [ ! -f "$tx/expired" ] || attempt_failed writer_lease_lost
[ ! -f "$tx/rolled-back" ] || attempt_failed already_rolled_back
[ "$(sha "$source_profile")" = "$("$jq" -r .new_source "$tx/journal.json")" ] && [ "$(sha "$live_profile")" = "$("$jq" -r .new_live "$tx/journal.json")" ] || attempt_failed post_reload_config_changed
touch "$tx/accepted"; recovery_release
cp "$work/reload-http" "$tx/reload-http"
cp "$work/route.log" "$tx/route-verification.log"
recovery_held=""
mv "$state/cache/.subscription-auto.$$" "$state/cache/subscription.yaml"
cache_tmp=""
success_status updated
say updated
# Keep a bounded number of this feature's accepted/rolled-back transaction backups.
count=0
for previous in $(ls -1d "$transactions"/tx-* 2>/dev/null | sort -r); do
  count=$((count+1)); [ "$count" -le 3 ] && continue
  [ -f "$previous/accepted" ] || [ -f "$previous/rolled-back" ] || continue
  [ ! -L "$previous" ] || continue
  rm -rf "$previous"
done
