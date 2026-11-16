#!/bin/sh
# Merlin/ShellCrash adapter. Offline derivation is delegated to yamlbridge;
# this script owns the explicit, recoverable installation transaction.
set -u
umask 077

action=plan
case "${1:---plan}" in
  --plan) action=plan ;; --apply) action=apply ;;
  --recover) action=recover ;; --status) action=status ;;
  *) echo 'usage: configure-service-health.sh --plan|--apply|--recover|--status' >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || exit 2
state=${SERVICE_HEALTH_STATE_ROOT:-${HOME_EDGE_STATE_ROOT:-/jffs/home-edge-bootstrap-state}}
runtime=${SERVICE_HEALTH_RUNTIME_CONFIG:-/tmp/ShellCrash/config.yaml}
groups=${SERVICE_HEALTH_GROUPS_FILE:-/jffs/ShellCrash/yamls/proxy-groups.yaml}
rules=${SERVICE_HEALTH_RULES_FILE:-/jffs/ShellCrash/yamls/rules.yaml}
core=${SERVICE_HEALTH_CORE_PATH:-/tmp/ShellCrash/CrashCore}
core_identity=$core
case "$core" in /proc/*/exe) core_identity=$(dirname "$runtime")/CrashCore ;; esac
pid_file=${SERVICE_HEALTH_PID_FILE:-$(dirname "$runtime")/shellcrash.pid}
bridge=${SERVICE_HEALTH_YAMLBRIDGE:-/tmp/home-edge-yamlbridge}
secret=${SERVICE_HEALTH_SECRET_FILE:-$state/CONTROLLER_SECRET.local}
api=${SERVICE_HEALTH_API:-}
health=$state/service-health.json
binding=$state/service-health.loaded.json
pending=$state/service-health-setup.pending
previous=$state/service-health-setup.previous
lock=${HOME_EDGE_WRITE_LOCK_DIR:-/tmp/home-edge-bootstrap-write.lock}
google_mode=${SERVICE_HEALTH_GOOGLE_MODE:-manual}
openai_mode=${SERVICE_HEALTH_OPENAI_MODE:-manual}
anthropic_mode=${SERVICE_HEALTH_ANTHROPIC_MODE:-manual}
health_mode=${SERVICE_HEALTH_MODE:-observe}
profiles=${SERVICE_HEALTH_PROFILES:-gemini}
work= stage= lock_owned=0

say() { printf '%s\n' "$*"; }
die() { printf 'configure-service-health: %s\n' "$*" >&2; exit 1; }
safe_path() {
  case "$1" in /*) ;; *) return 1 ;; esac
  case "$1" in /|*[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.|*//*) return 1 ;; esac
  # A parent symlink can redirect a seemingly regular target outside its scope.
  path_check=$1
  while [ "$path_check" != / ]; do
    [ ! -L "$path_check" ] || return 1
    path_check=$(dirname "$path_check")
  done
}
for path in "$state" "$runtime" "$groups" "$rules" "$bridge" "$secret" "$lock" "$pid_file" "$core_identity"; do
  safe_path "$path" || die 'unsafe configured path'
done
for mode in "$google_mode" "$openai_mode" "$anthropic_mode"; do
  case "$mode" in auto|manual) ;; *) die 'service mode must be auto or manual' ;; esac
done
case "$health_mode" in auto|observe) ;; *) die 'health mode must be auto or observe' ;; esac
# Targets must be distinct, including state metadata and secret material.
[ "$(printf '%s\n' "$runtime" "$groups" "$rules" "$health" "$binding" "$secret" | sort -u | wc -l | tr -d ' ')" -eq 6 ] || die 'overlapping targets'
for path in "$runtime" "$groups" "$rules" "$health" "$binding" "$secret"; do
  case "$path" in "$pending"|"$pending"/*|"$previous"|"$previous"/*) die 'target overlaps transaction storage' ;; esac
done

if [ "$action" = status ]; then
  if [ -e "$pending" ] || [ -L "$pending" ]; then
    [ -d "$pending" ] && [ ! -L "$pending" ] && [ -f "$pending/receipt.json" ] && [ ! -L "$pending/receipt.json" ] || die 'unrecognized pending state'
    status=$(jq -er '.status | select(type=="string")' "$pending/receipt.json" 2>/dev/null) || die 'invalid pending receipt'
    case "$status" in prepared|committing|reloading|unresolved|accepted) say "service_health_setup_state=pending_$status" ;; *) die 'unknown pending status' ;; esac
  elif [ -f "$health" ]; then say 'service_health_setup_state=configured'
  else say 'service_health_setup_state=absent'; fi
  exit 0
fi
[ "$action" != apply ] || [ "${SERVICE_HEALTH_CONFIRM:-}" = APPLY ] || die 'apply requires SERVICE_HEALTH_CONFIRM=APPLY'
for tool in jq curl cp mv mkdir rmdir rm chmod readlink; do which "$tool" >/dev/null 2>&1 || die 'required adapter tool unavailable'; done
if which sha256sum >/dev/null 2>&1; then hash_tool=sha256sum
elif which openssl >/dev/null 2>&1; then hash_tool=openssl
else die 'SHA-256 implementation unavailable'; fi
hash_file() {
  if [ "$hash_tool" = sha256sum ]; then sha256sum "$1" | awk '{print $1}'
  else openssl dgst -sha256 "$1" | awk '{print $NF}'; fi
}
helper=${HOME_EDGE_SECURE_TEMP_HELPER:-}
script_dir=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || die 'cannot locate script directory'
if [ -z "$helper" ]; then
  helper=$script_dir/home-edge-secure-temp.sh
  [ -r "$helper" ] || helper=/jffs/scripts/home-edge-secure-temp.sh
fi
[ -r "$helper" ] || die 'secure temporary helper unavailable'
. "$helper"
core_pid() {
  if [ -f "$pid_file" ] && [ ! -L "$pid_file" ]; then
    current_pid=$(cat "$pid_file" 2>/dev/null) || return 1
    case "$current_pid" in ''|*[!0-9]*) return 1 ;; esac
    current_exe=$(readlink "/proc/$current_pid/exe" 2>/dev/null) || return 1
    case "$current_exe" in "$core_identity"|"$core_identity (deleted)") ;; *) return 1 ;; esac
  else
    which pidof >/dev/null 2>&1 || return 1
    current_pid=$(pidof "$(basename "$core_identity")" 2>/dev/null) || return 1
    case "$current_pid" in ''|*[!0-9]*) return 1 ;; esac
    current_exe=$(readlink "/proc/$current_pid/exe" 2>/dev/null) || return 1
    case "$current_exe" in "$core_identity"|"$core_identity (deleted)") ;; *) return 1 ;; esac
  fi
  printf '%s\n' "$current_pid"
}

clean_transaction_dir() {
  clean_dir=$1
  safe_path "$clean_dir" && [ -d "$clean_dir" ] || return 1
  # Do not erase an unfamiliar entry merely because it is under our directory.
  for clean_item in "$clean_dir"/* "$clean_dir"/.[!.]* "$clean_dir"/..?*; do
    [ -e "$clean_item" ] || [ -L "$clean_item" ] || continue
    case "${clean_item##*/}" in receipt.json|graph.before.json|before.runtime|before.groups|before.rules|before.health|before.binding|proposed.runtime|proposed.groups|proposed.rules|proposed.health|proposed.binding) ;; *) return 1 ;; esac
  done
  for clean_name in receipt.json graph.before.json before.runtime before.groups before.rules before.health before.binding proposed.runtime proposed.groups proposed.rules proposed.health proposed.binding; do
    [ ! -L "$clean_dir/$clean_name" ] || return 1
    [ ! -e "$clean_dir/$clean_name" ] || [ -f "$clean_dir/$clean_name" ] || return 1
  done
  for clean_name in receipt.json graph.before.json before.runtime before.groups before.rules before.health before.binding proposed.runtime proposed.groups proposed.rules proposed.health proposed.binding; do rm -f "$clean_dir/$clean_name" || return 1; done
  rmdir "$clean_dir"
}
cleanup() {
  [ -z "$stage" ] || rm -f "$stage" 2>/dev/null || true
  if [ -n "$work" ] && [ -d "$work" ] && [ ! -L "$work" ]; then
    for name in runtime.yaml groups.yaml rules.yaml manifest.json; do rm -f "$work/candidate/$name" 2>/dev/null || true; done
    rmdir "$work/candidate" 2>/dev/null || true
    for name in request.json health.json health-validated.json health-services.json seeds.json profiles.json runtime.json version.json core-test.json core-test-report.json bind-request.json bind-check.json bind-check-report.json binding-error.log loaded.json graph.before.json graph.fresh.json graph.after.json selectors.before.json selectors.after.json sources.json curl.conf api.body core-test.log receipt.json yamlbridge; do rm -f "$work/$name" 2>/dev/null || true; done
    rmdir "$work" 2>/dev/null || true
  fi
  if [ "$lock_owned" -eq 1 ]; then
    if [ -f "$lock/pid" ] && [ "$(cat "$lock/pid" 2>/dev/null)" = "$$" ]; then
      rm -f "$lock/pid" "$lock/operation" "$lock/started_at"
      rmdir "$lock" 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
acquire_lock() {
  mkdir "$lock" 2>/dev/null || die 'global write lock is active; no takeover attempted'
  lock_owned=1
  printf '%s\n' "$$" >"$lock/pid" || die 'cannot record lock owner'
  printf '%s\n' service-health-setup >"$lock/operation" || die 'cannot record lock operation'
  date +%s >"$lock/started_at" || die 'cannot record lock time'
}
fingerprint() {
  safe_path "$1" || return 1
  if [ -e "$1" ]; then
    [ -f "$1" ] || return 1
    digest=$(hash_file "$1") || return 1
    printf '%s\n' "$digest" | grep -Eq '^[0-9a-f]{64}$' || return 1
    printf '%s\n' "$digest"
  else printf '%s\n' absent; fi
}
target_for() {
  case "$1" in runtime) printf '%s\n' "$runtime" ;; groups) printf '%s\n' "$groups" ;; rules) printf '%s\n' "$rules" ;; health) printf '%s\n' "$health" ;; binding) printf '%s\n' "$binding" ;; *) return 1 ;; esac
}
atomic_install() {
  install_source=$1 install_target=$2 install_expected=$3
  safe_path "$install_target" && [ -d "$(dirname "$install_target")" ] || return 1
  stage=$(home_edge_secure_temp "$(dirname "$install_target")/.home-edge-service-stage.XXXXXX") || return 1
  cp "$install_source" "$stage" && chmod 600 "$stage" || return 1
  [ "$(fingerprint "$install_target")" = "$install_expected" ] || return 1
  mv -f "$stage" "$install_target" || return 1
  stage=
}
set_receipt_status() {
  receipt_status=$1
  stage=$(home_edge_secure_temp "$pending/.receipt.XXXXXX") || return 1
  jq --arg status "$receipt_status" '.status=$status' "$pending/receipt.json" >"$stage" || return 1
  mv -f "$stage" "$pending/receipt.json" || return 1
  stage=
  sync
}
validate_receipt() {
  [ -d "$pending" ] && [ ! -L "$pending" ] && [ -f "$pending/receipt.json" ] && [ ! -L "$pending/receipt.json" ] || return 1
  jq -e '.schema_version==1 and .kind=="home-edge-service-setup-transaction" and
    ([.files[].role]|sort)==["binding","groups","health","rules","runtime"] and
    all(.files[]; (.path|type)=="string" and (.before_sha256|test("^(absent|[0-9a-f]{64})$")) and (if .role=="binding" then (.proposed_sha256|test("^(absent|[0-9a-f]{64})$")) else (.proposed_sha256|test("^[0-9a-f]{64}$")) end))' "$pending/receipt.json" >/dev/null 2>&1 || return 1
  for role in runtime groups rules health binding; do
    target=$(target_for "$role") || return 1
    recorded=$(jq -er --arg role "$role" '.files[]|select(.role==$role)|.path' "$pending/receipt.json") || return 1
    [ "$recorded" = "$target" ] || return 1
  done
}
restore_owned() {
  validate_receipt || return 1
  restore_ok=1
  for role in runtime groups rules health binding; do
    target=$(target_for "$role")
    before=$(jq -er --arg role "$role" '.files[]|select(.role==$role)|.before_sha256' "$pending/receipt.json") || return 1
    proposed=$(jq -er --arg role "$role" '.files[]|select(.role==$role)|.proposed_sha256' "$pending/receipt.json") || return 1
    current=$(fingerprint "$target") || { restore_ok=0; continue; }
    [ "$current" != "$before" ] || continue
    [ "$current" = "$proposed" ] || { restore_ok=0; continue; }
    if [ "$before" = absent ]; then
      [ "$(fingerprint "$target")" = "$proposed" ] && rm -f "$target" || restore_ok=0
    else
      [ "$(fingerprint "$pending/before.$role")" = "$before" ] || { restore_ok=0; continue; }
      atomic_install "$pending/before.$role" "$target" "$proposed" || restore_ok=0
    fi
  done
  sync
  [ "$restore_ok" -eq 1 ]
}
archive_accepted() {
  if [ -e "$previous" ]; then
    [ -f "$previous/receipt.json" ] && [ ! -L "$previous/receipt.json" ] && jq -e '.kind=="home-edge-service-setup-transaction" and .status=="accepted"' "$previous/receipt.json" >/dev/null 2>&1 || return 1
    clean_transaction_dir "$previous" || return 1
  fi
  mv "$pending" "$previous" || return 1
  sync
}

if [ "$action" = recover ]; then
  if [ ! -e "$pending" ] && [ ! -L "$pending" ]; then say 'service_health_setup_state=clean'; exit 0; fi
  acquire_lock
  validate_receipt || die 'pending receipt cannot be safely interpreted'
  status=$(jq -er '.status' "$pending/receipt.json") || die 'pending status unavailable'
  if [ "$status" = accepted ]; then
    archive_accepted || die 'accepted transaction archive is unresolved'
    say 'service_health_setup_state=accepted'; exit 0
  fi
  # Recovery is a boot-time file reconciliation, not an implicit live reload.
  # Clearing its receipt while an old/candidate core still runs would lose the
  # unresolved runtime responsibility.
  if core_pid >/dev/null 2>&1; then die 'file recovery requires the core to be stopped before boot'; fi
  if which pidof >/dev/null 2>&1; then
    [ -z "$(pidof "$(basename "$core_identity")" 2>/dev/null || true)" ] || die 'file recovery requires the core to be stopped before boot'
  else die 'cannot establish stopped core without process inventory'; fi
  restore_owned || { set_receipt_status unresolved || true; die 'recovery unresolved; later edits were preserved'; }
  stage=$(home_edge_secure_temp "$state/.service-health-last.XXXXXX") || die 'cannot record recovery'
  jq '.status="recovered_before_boot"' "$pending/receipt.json" >"$stage" && mv -f "$stage" "$state/service-health-setup.last.json" || die 'cannot retain recovery receipt'
  stage=
  sync
  clean_transaction_dir "$pending" || die 'recovery files restored; journal cleanup unresolved'
  say 'service_health_setup_state=recovered_before_boot'
  say 'runtime_reload_state=not_requested'
  exit 0
fi

[ ! -e "$pending" ] && [ ! -L "$pending" ] || die 'pending transaction requires --recover before new setup'
[ -f "$runtime" ] && [ ! -L "$runtime" ] || die 'runtime config unavailable'
[ -f "$secret" ] && [ ! -L "$secret" ] || die 'private controller secret unavailable'
[ "$action" != apply ] || acquire_lock
if [ -z "$api" ] && [ -f /tmp/self-heal.api ] && [ ! -L /tmp/self-heal.api ]; then api=$(cat /tmp/self-heal.api 2>/dev/null); fi
api=${api:-http://127.0.0.1:9999}
printf '%s\n' "$api" | grep -Eq '^http://127\.0\.0\.1:[0-9]{1,5}$' || die 'controller must be loopback HTTP without URL credentials'
work=$(home_edge_secure_temp -d /tmp/home-edge-service-setup.XXXXXX) || die 'cannot allocate private workspace'
if [ -z "${SERVICE_HEALTH_YAMLBRIDGE:-}" ]; then
  tools_helper=${SERVICE_HEALTH_TOOLS_HELPER:-$script_dir/subscription-tools.sh}
  [ -r "$tools_helper" ] || tools_helper=/jffs/scripts/home-edge-subscription-tools.sh
  [ -r "$tools_helper" ] || die 'verified parser resolver unavailable; install or upgrade the project runtime'
  for parser_source in "$state/runtime/yamlbridge.gz" "$state/runtime/yamlbridge.sha256"; do
    safe_path "$parser_source" && [ -f "$parser_source" ] || die 'protected parser runtime is unavailable'
  done
  bridge=$(HOME_EDGE_STATE_ROOT="$state" SUBSCRIPTION_PARSER_BIN="$work/yamlbridge" sh "$tools_helper" 2>/dev/null) || die 'protected parser runtime verification failed'
  [ "$bridge" = "$work/yamlbridge" ] && [ -x "$bridge" ] || die 'parser resolver returned an unexpected executable'
else
  [ -x "$bridge" ] || die 'explicit yamlbridge executable unavailable'
fi
if [ ! -x "$core" ] || [ -L "$core" ]; then
  existing_pid=$(core_pid) || die 'verified current core executable unavailable'
  core=/proc/$existing_pid/exe
  [ -x "$core" ] || die 'current core executable cannot be invoked'
else
  safe_path "$core" || die 'unsafe core executable path'
fi
# The secret remains in a 0600 curl config, never in process arguments or output.
jq -nr --rawfile secret "$secret" '
  ($secret|rtrimstr("\n")) as $s |
  if ($s|length)>0 and ($s|length)<=4096 and ($s|test("[\r\n\u0000]")|not)
  then "header = " + (("Authorization: Bearer " + $s)|tojson)
  else error("invalid private controller secret") end' >"$work/curl.conf" 2>/dev/null || die 'invalid private controller secret'
controller_get() {
  curl --config "$work/curl.conf" --noproxy '*' --silent --fail --max-time 8 "$api/proxies" >"$1" 2>/dev/null || return 1
  [ "$(wc -c <"$1" | tr -d ' ')" -le 10485760 ] || return 1
  jq -e '.proxies|type=="object"' "$1" >/dev/null 2>&1
}
graph_projection() { jq -S '.proxies | map_values({type,now,all,id})' "$1"; }
controller_reload() {
  jq -n --rawfile payload "$runtime" '{payload:$payload}' >"$work/api.body" || return 1
  curl --config "$work/curl.conf" --noproxy '*' --silent --fail --max-time 12 -X PUT -H 'Content-Type: application/json' --data-binary "@$work/api.body" "$api/configs" >/dev/null 2>&1
}
verify_old_selectors() {
  jq -S '.proxies|with_entries(select(.value.type=="Selector"))|map_values({type,now,all})' "$work/graph.before.json" >"$work/selectors.before.json" || return 1
  # Mihomo's implicit GLOBAL appends newly introduced groups. Preserve all old
  # members in order and the selected value; permit only selected profile groups.
  jq -e --slurpfile old "$work/selectors.before.json" --slurpfile profiles "$work/profiles.json" '
    .proxies as $g | $old[0] as $before |
    ($profiles[0]|map("Edge-"+., "Edge-"+.+"-Auto")) as $allowed |
    all($before|to_entries[]; . as $entry | $g[$entry.key] as $after |
      if $entry.key=="GLOBAL" then
        $after.type==$entry.value.type and $after.now==$entry.value.now and
        ($after.all|type)=="array" and
        ([$after.all[]|select(. as $n|$entry.value.all|index($n))]==$entry.value.all) and
        all($after.all[]; . as $n | (($entry.value.all|index($n))!=null or ($allowed|index($n))!=null)) and
        ($after.all|length)==($after.all|unique|length)
      else {type:$after.type,now:$after.now,all:$after.all}==$entry.value end)
  ' "$work/graph.after.json" >/dev/null 2>&1
}
controller_get "$work/graph.before.json" || die 'controller graph unavailable'
initial_pid=$(core_pid) || die 'exactly one existing core PID is required'
runtime_dir=${SERVICE_HEALTH_RUNTIME_DIR:-}
if [ -z "$runtime_dir" ] && [ -r "/proc/$initial_pid/cmdline" ]; then
  runtime_dir=$(tr '\000' '\n' <"/proc/$initial_pid/cmdline" | awk 'wanted {print; wanted=0} $0=="-d" {wanted=1}')
fi
safe_path "$runtime_dir" && [ -d "$runtime_dir" ] || die 'verified core home unavailable; set SERVICE_HEALTH_RUNTIME_DIR'
jq -ne --arg profiles "$profiles" '
  ($profiles|gsub(",";" ")|split(" ")|map(select(length>0))) as $p |
  if ($p|length)>0 and ($p|length)<=3 and ($p|unique|length)==($p|length) and
    all($p[]; .=="gemini" or .=="openai" or .=="anthropic") then $p else error("invalid profiles") end
' >"$work/profiles.json" 2>/dev/null || die 'SERVICE_HEALTH_PROFILES must name distinct supported services'
seed_group=${SERVICE_HEALTH_SEED_GROUP:-}
# Keep each service's current Edge selection when it already exists. Otherwise
# identify a native AI selector; Chinese subscription group names are supported.
jq -e --arg seed "$seed_group" --arg gs "${SERVICE_HEALTH_GEMINI_SEED_GROUP:-}" --arg os "${SERVICE_HEALTH_OPENAI_SEED_GROUP:-}" --arg as "${SERVICE_HEALTH_ANTHROPIC_SEED_GROUP:-}" --slurpfile profiles "$work/profiles.json" '
  .proxies as $g |
  def resolve($n;$seen):
    if ($seen|length)>=16 or ($seen|index($n))!=null or $g[$n]==null then error("unresolved seed")
    elif $g[$n].type=="Selector" then
      $g[$n].now as $next | if ($next|type)!="string" or ($g[$n].all|index($next))==null then error("invalid selector") else resolve($next;$seen+[$n]) end
    elif (($g[$n].all // [])|length)>0 or (["DIRECT","REJECT","GLOBAL"]|index($n))!=null then error("nonconcrete seed")
    else $n end;
  reduce $profiles[0][] as $profile ({};
    ({gemini:$gs,openai:$os,anthropic:$as}[$profile]) as $ownseed |
    (if $ownseed!="" then [$ownseed]
     elif $seed!="" then [$seed]
     elif $g["Edge-"+$profile].type=="Selector" then ["Edge-"+$profile]
     else (if $profile=="gemini" then "(^|[^a-z])ai([^a-z]|$)|人工智能" elif $profile=="openai" then "openai|chatgpt" else "anthropic|claude" end) as $pattern |
       [$g|to_entries[]|select(.value.type=="Selector" and (.key|startswith("Edge-")|not) and (.key|test($pattern;"i")))|.key] end) as $seeds |
    if ($seeds|length)!=1 or $g[$seeds[0]].type!="Selector" then error("ambiguous seed group") else .[$profile]=resolve($seeds[0];[]) end)
' "$work/graph.before.json" >"$work/seeds.json" 2>/dev/null || die 'cannot resolve exact selected service seed; set SERVICE_HEALTH_SEED_GROUP'
for role in runtime groups rules health binding; do
  target=$(target_for "$role")
  sha=$(fingerprint "$target") || die 'source target is not a regular owned path'
  jq -n --arg role "$role" --arg path "$target" --arg sha "$sha" '{role:$role,path:$path,before_sha256:$sha}'
done | jq -s '.' >"$work/sources.json" || die 'cannot capture source hashes'
group_input= rule_input=
[ ! -f "$groups" ] || group_input=$groups
[ ! -f "$rules" ] || rule_input=$rules
printf '[]\n' >"$work/health-services.json" || die 'cannot initialize health registrations'
if [ -f "$health" ]; then
  [ "$(wc -c <"$health" | tr -d ' ')" -le 65536 ] || die 'existing health registration too large'
  "$bridge" service-health-validate "$health" "$work/health-validated.json" >/dev/null 2>&1 || die 'existing health registration is invalid or ambiguous'
  jq -e --slurpfile profiles "$work/profiles.json" --slurpfile graph "$work/graph.before.json" '
    if .schema_version==1 and (.mode=="auto" or .mode=="observe") and
      (.services|type)=="array" and (.services|length)>0 and (.services|length)<=3 and
      ([.services[].name]|unique|length)==(.services|length) and
      all(.services[]; (keys|sort)==["auto_selector","name","selector"] and
        (.name=="gemini" or .name=="openai" or .name=="anthropic") and
        .selector==("Edge-"+.name) and .auto_selector==("Edge-"+.name+"-Auto"))
    then [.services[]|select(.name as $name|($profiles[0]|index($name))==null)|
      if $graph[0].proxies[.selector].type=="Selector" and $graph[0].proxies[.auto_selector].type=="Selector" then . else error("missing preserved service") end]
    else error("invalid health registration") end
  ' "$work/health-validated.json" >"$work/health-services.json" 2>/dev/null || die 'existing health registrations cannot be safely preserved'
  if [ -z "${SERVICE_HEALTH_MODE+x}" ]; then health_mode=$(jq -er '.mode' "$work/health-validated.json") || die 'existing health mode unavailable'; fi
fi
jq -n --arg runtime "$runtime" --arg groups "$group_input" --arg rules "$rule_input" --slurpfile profiles "$work/profiles.json" --slurpfile seeds "$work/seeds.json" --arg gm "$google_mode" --arg om "$openai_mode" --arg am "$anthropic_mode" \
  '{schema_version:1,runtime_config:$runtime,groups_overlay:$groups,rules_overlay:$rules,services:($profiles[0]|map(. as $name|{name:$name,initial_node:$seeds[0][$name],mode:({gemini:$gm,openai:$om,anthropic:$am}[$name])}))}' >"$work/request.json" || die 'cannot render offline setup request'
"$bridge" service-setup "$work/request.json" "$work/candidate" >/dev/null 2>&1 || die 'offline setup rejected source or reserved ownership'
jq -n --arg core "$core" --arg config "$work/candidate/runtime.yaml" --arg runtime_dir "$runtime_dir" \
  '{schema_version:1,core_path:$core,config_file:$config,runtime_dir:$runtime_dir,timeout_sec:20}' >"$work/core-test.json" || die 'cannot render bounded core validation request'
"$bridge" core-test "$work/core-test.json" "$work/core-test-report.json" >/dev/null 2>&1 || die 'bounded candidate core validation failed'
"$bridge" decode "$work/candidate/runtime.yaml" "$work/runtime.json" >/dev/null 2>&1 || die 'cannot inspect candidate adapter capability'
curl --config "$work/curl.conf" --noproxy '*' --silent --fail --max-time 8 "$api/version" >"$work/version.json" 2>/dev/null || die 'controller version unavailable'
[ "$(wc -c <"$work/version.json" | tr -d ' ')" -le 65536 ] || die 'controller version response too large'
binding_supported=0
if jq -e '(.version=="v1.19.34" or .version=="1.19.34")' "$work/version.json" >/dev/null 2>&1 &&
  jq -e '((.["proxy-providers"] // {})|type)=="object" and ((.["proxy-providers"] // {})|length)==0 and (.proxies|type)=="array" and (.proxies|length)>0' "$work/runtime.json" >/dev/null 2>&1; then
  binding_supported=1
else health_mode=observe; fi
if [ "$binding_supported" -eq 1 ]; then
  candidate_hash=$(fingerprint "$work/candidate/runtime.yaml") || die 'cannot hash binding candidate'
  jq -n --arg api "$api" --arg secret "$secret" --arg runtime "$work/candidate/runtime.yaml" --arg core "$core" --arg hash "$candidate_hash" --arg before "$work/graph.before.json" \
    '{schema_version:1,api:$api,secret_file:$secret,runtime_config:$runtime,core_path:$core,expected_runtime_sha256:$hash,expected_before_graph_file:$before}' >"$work/bind-check.json" || die 'cannot render binding preflight'
  "$bridge" service-bind-check "$work/bind-check.json" "$work/bind-check-report.json" >/dev/null || die 'read-only binding preflight failed; no files applied'
fi
jq -n --arg mode "$health_mode" --arg api "$api" --arg secret "$secret" --arg runtime "$runtime" --arg core "$core" --arg state "$state/service-health-runtime" --arg binding "$binding" --slurpfile profiles "$work/profiles.json" --slurpfile preserved "$work/health-services.json" \
  '{schema_version:1,mode:$mode,api:$api,secret_file:$secret,runtime_config:$runtime,core_path:$core,state_dir:$state,loaded_binding_file:$binding,fail_checks:3,cooldown_sec:1800,max_attempts_per_hour:2,max_candidates:3,probe_timeout_sec:15,services:(($profiles[0]|map({name:.,selector:("Edge-"+.),auto_selector:("Edge-"+.+"-Auto")}))+$preserved[0])}' >"$work/health.json" || die 'cannot render health registration'
if [ "$action" = plan ]; then
  say 'service_health_setup_state=planned'
  say 'candidate_core_validation=passed'
  say "service_health_mode=$health_mode"
  say "gemini_initial_mode=$google_mode"
  if [ "$binding_supported" -eq 1 ]; then say 'repair_capability=loaded_binding_supported'; else say 'repair_capability=observe_only'; fi
  say 'runtime_reload_state=not_requested'
  exit 0
fi

# All ownership checks run again under the global lock immediately before commit.
for role in runtime groups rules health binding; do
  target=$(target_for "$role")
  before=$(jq -er --arg role "$role" '.[]|select(.role==$role)|.before_sha256' "$work/sources.json") || die 'source receipt incomplete'
  [ "$(fingerprint "$target")" = "$before" ] || die 'source changed before commit'
  [ -d "$(dirname "$target")" ] || die 'target parent directory unavailable'
done
controller_get "$work/graph.fresh.json" || die 'fresh controller graph unavailable'
graph_projection "$work/graph.before.json" >"$work/selectors.before.json" || die 'cannot project controller graph'
graph_projection "$work/graph.fresh.json" >"$work/selectors.after.json" || die 'cannot project fresh graph'
cmp -s "$work/selectors.before.json" "$work/selectors.after.json" || die 'controller graph changed before commit'
[ "$(core_pid)" = "$initial_pid" ] || die 'core PID changed before commit'
[ -d "$state" ] || mkdir -p "$state" || die 'state directory unavailable'
chmod 700 "$state" || die 'cannot secure state directory'
mkdir "$pending" || die 'pending transaction appeared concurrently'
for role in runtime groups rules health binding; do
  target=$(target_for "$role")
  before=$(jq -er --arg role "$role" '.[]|select(.role==$role)|.before_sha256' "$work/sources.json") || die 'source receipt incomplete'
  if [ "$before" != absent ]; then cp "$target" "$pending/before.$role" || die 'cannot retain transaction backup'; fi
  if [ "$role" = binding ]; then : # Receipt is finalized only after binding observation succeeds.
  elif [ "$role" = health ]; then cp "$work/health.json" "$pending/proposed.$role" || die 'cannot retain proposed registration'
  else cp "$work/candidate/$role.yaml" "$pending/proposed.$role" || die 'cannot retain proposed configuration'; fi
done
cp "$work/graph.before.json" "$pending/graph.before.json" || die 'cannot retain selector receipt'
for role in runtime groups rules health binding; do
  proposed=$(fingerprint "$pending/proposed.$role") || die 'cannot hash proposed output'
  jq --arg role "$role" --arg proposed "$proposed" '.[]|select(.role==$role)|.proposed_sha256=$proposed' "$work/sources.json"
done | jq -s --arg pid "$initial_pid" '{schema_version:1,kind:"home-edge-service-setup-transaction",status:"prepared",core_pid:$pid,files:.}' >"$pending/receipt.json" || die 'cannot persist transaction receipt'
sync
validate_receipt || die 'persisted transaction failed verification'
for role in runtime groups rules health binding; do
  before=$(jq -er --arg role "$role" '.files[]|select(.role==$role)|.before_sha256' "$pending/receipt.json") || die 'invalid source receipt'
  if [ "$before" != absent ]; then [ "$(fingerprint "$pending/before.$role")" = "$before" ] || die 'source changed while backup was captured'; fi
done
apply_failed=0
set_receipt_status committing || die 'cannot persist committing receipt'
for role in groups rules health runtime; do
  apply_phase=install_$role
  target=$(target_for "$role")
  before=$(jq -er --arg role "$role" '.files[]|select(.role==$role)|.before_sha256' "$pending/receipt.json") || { apply_failed=1; break; }
  atomic_install "$pending/proposed.$role" "$target" "$before" || { apply_failed=1; break; }
done
if [ "$apply_failed" -eq 0 ]; then
  apply_phase=binding_reload
  set_receipt_status reloading || apply_failed=1
  proposed_runtime=$(jq -er '.files[]|select(.role=="runtime")|.proposed_sha256' "$pending/receipt.json") || apply_failed=1
  jq -n --arg api "$api" --arg secret "$secret" --arg runtime "$runtime" --arg core "$core" --arg hash "$proposed_runtime" --arg before "$pending/graph.before.json" \
    '{schema_version:1,api:$api,secret_file:$secret,runtime_config:$runtime,core_path:$core,expected_runtime_sha256:$hash,expected_before_graph_file:$before}' >"$work/bind-request.json" || apply_failed=1
  if [ "$apply_failed" -eq 0 ] && [ "$binding_supported" -eq 1 ]; then
    if ! "$bridge" service-bind-reload "$work/bind-request.json" "$work/loaded.json" >/dev/null 2>"$work/binding-error.log"; then
      apply_failed=1
      binding_reason=$(grep -Eo 'binding_[a-z_]+' "$work/binding-error.log" | head -n 1)
      case "$binding_reason" in binding_[a-z_]*) say "service_health_binding_error=$binding_reason" ;; esac
    fi
  elif [ "$apply_failed" -eq 0 ]; then
    controller_reload || apply_failed=1
  fi
  if [ "$apply_failed" -eq 0 ] && [ "$binding_supported" -eq 1 ]; then
    apply_phase=install_binding
    cp "$work/loaded.json" "$pending/proposed.binding" || apply_failed=1
    proposed_binding=$(fingerprint "$pending/proposed.binding") || apply_failed=1
    stage=$(home_edge_secure_temp "$pending/.receipt.XXXXXX") || apply_failed=1
    if [ "$apply_failed" -eq 0 ]; then
      jq --arg hash "$proposed_binding" '(.files[]|select(.role=="binding")|.proposed_sha256)=$hash' "$pending/receipt.json" >"$stage" &&
        mv -f "$stage" "$pending/receipt.json" || apply_failed=1
      stage=
      sync
    fi
    before_binding=$(jq -er '.files[]|select(.role=="binding")|.before_sha256' "$pending/receipt.json") || apply_failed=1
    if [ "$apply_failed" -eq 0 ]; then atomic_install "$pending/proposed.binding" "$binding" "$before_binding" || apply_failed=1; fi
  elif [ "$apply_failed" -eq 0 ]; then
    before_binding=$(jq -er '.files[]|select(.role=="binding")|.before_sha256' "$pending/receipt.json") || apply_failed=1
    if [ "$(fingerprint "$binding")" = "$before_binding" ]; then rm -f "$binding" || apply_failed=1; else apply_failed=1; fi
  fi
  [ "$apply_failed" -ne 0 ] || apply_phase=verify_selectors
  controller_get "$work/graph.after.json" || apply_failed=1
  [ "$(core_pid)" = "$initial_pid" ] || apply_failed=1
  verify_old_selectors || apply_failed=1
  jq -e --slurpfile request "$work/request.json" '
    .proxies as $g | all($request[0].services[];
      . as $s | ("Edge-"+$s.name) as $name |
      $g[$name].type=="Selector" and $g[$name+"-Auto"].type=="Selector" and
      $g[$name].now==(if $s.mode=="auto" then $name+"-Auto" else $s.initial_node end) and $g[$name+"-Auto"].now==$s.initial_node)
  ' "$work/graph.after.json" >/dev/null 2>&1 || apply_failed=1
  for role in runtime groups rules health binding; do
    target=$(target_for "$role")
    proposed=$(jq -er --arg role "$role" '.files[]|select(.role==$role)|.proposed_sha256' "$pending/receipt.json") || { apply_failed=1; break; }
    [ "$(fingerprint "$target")" = "$proposed" ] || apply_failed=1
  done
fi
if [ "$apply_failed" -ne 0 ]; then
  say "service_health_apply_failed=$apply_phase"
  rollback_restored=0
  if restore_owned; then
    rollback_restored=1
    for role in runtime groups rules health binding; do
      target=$(target_for "$role")
      before=$(jq -er --arg role "$role" '.files[]|select(.role==$role)|.before_sha256' "$pending/receipt.json") || { rollback_restored=0; break; }
      [ "$(fingerprint "$target")" = "$before" ] || rollback_restored=0
    done
  fi
  # Reload only while the original process is still present. An unverified
  # rollback is retained as pending so boot recovery cannot silently skip it.
  if [ "$rollback_restored" -eq 1 ] && [ "$(core_pid)" = "$initial_pid" ] && controller_get "$work/graph.after.json" && verify_old_selectors; then controller_reload || true; fi
  set_receipt_status unresolved || true
  die 'apply or verification failed; owned files restored where safe, pending recovery retained'
fi
set_receipt_status accepted || die 'verified configuration awaits receipt recovery'
archive_accepted || die 'configuration verified; accepted backup archive remains pending'
say 'service_health_setup_state=accepted'
say 'old_selectors_preserved=verified'
say 'core_pid_preserved=verified'
say 'runtime_reload_state=verified'
if [ "$binding_supported" -eq 1 ]; then say 'repair_capability=loaded_binding_supported'; else say 'repair_capability=observe_only'; fi
