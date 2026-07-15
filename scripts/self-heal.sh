#!/bin/sh
# self-heal.sh — selector self-heal for Mihomo/ShellCrash; DRY-RUN by default
#
# Goal: keep the main selector on a reachable route while minimizing unnecessary switching.
# Region, provider, protocol, node naming, and service-specific policy are optional site-local
# constraints, not project defaults. The implementation only uses the local clash/mihomo API and
# works with inline proxies, proxy-providers, concrete routes, or nested selector groups.
#
# Runs on the ROUTER (BusyBox ash). Deps: curl, jq, sort, mktemp (ShellClash ships these).
# Safe to test: with HEAL_DRY_RUN=1 (default) it only LOGS what it would switch to.
#
# Env knobs (all optional):
#   CLASH_API   clash/mihomo API endpoint; when blank, auto-discovered
#   CLASH_SECRET   API secret (blank by default)
#   HEAL_GROUP  explicit selector group name; blank means auto-discover
#   HEAL_GROUP_MATCH_REGEX  preferred main-selector group-name regex
#   HEAL_GROUP_EXCLUDE_REGEX  group-name regex to deprioritize during auto-discovery
#   HEAL_PROBE_URL  reachability probe      default: https://cp.cloudflare.com/generate_204
#   HEAL_ROUTE_REGION_REGEX  optional region/site route constraint; empty means any region
#   HEAL_CANDIDATE_ROUTE_REGEX / HEAL_CANDIDATE_EXCLUDE_REGEX  eligible route names
#   HEAL_PREFERRED_ROUTE_REGEX  optional stable route preference before raw latency
#   HEAL_DELAY_PROBES  repeated latency probes per candidate, default 2
#   HEAL_DELAY_TIMEOUT_MS  timeout per latency probe, default 3000
#   HEAL_MUTATE_NESTED_GROUPS  1=may switch one nested selector group, default 0
#   HEAL_DRY_RUN   1=log only (default), 0=actually switch
#   HEAL_LOG    default /tmp/self-heal.log
#   HEAL_VERIFY_ONLY   1=probe current route only and never switch
#   HEAL_OBSERVE_ONLY  1=report controller reachability/authentication only
#   HEAL_MAX_SWITCHES_PER_HOUR  circuit breaker, default 6
#   HEAL_ROLE_GROUPS_ENABLED  1=also keep role groups on safe defaults, default 1
#   HEAL_ROLE_AD_BLOCK_GROUP_REGEX / HEAL_ROLE_AD_BLOCK_TARGET  ad role guardrail
#   HEAL_ROLE_ROUTE_GROUP_MATCH_REGEX / HEAL_ROLE_ROUTE_TARGET_REGEX  opt-in role-route guardrail
set -u
umask 077

if [ -n "${HEAL_POLICY_FILE:-}" ] && [ -r "$HEAL_POLICY_FILE" ]; then
  . "$HEAL_POLICY_FILE"
else
  for f in /jffs/scripts/home-edge-policy.env /jffs/home-edge-bootstrap/config/policy.env ./config/policy.env; do
    [ -r "$f" ] && { . "$f"; break; }
  done
fi

API="${CLASH_API:-}"
SECRET="${CLASH_SECRET:-}"
GROUP="${HEAL_GROUP:-}"
GROUP_MATCH_RE="${HEAL_GROUP_MATCH_REGEX:-节点选择|代理选择|主选择|手动切换|自动选择|选择代理|全局选择|默认代理|国外|境外|(^|[^A-Za-z0-9])(PROXY|SELECT|Selector|Manual|Fallback|Auto|URL[ _.-]*Test|Load[ _.-]*Balance|Node[ _.-]*(Select|Selector|Choice)|Proxy[ _.-]*(Select|Selector|Choice)|Global[ _.-]*(Proxy|Select|Selector)|Main[ _.-]*(Proxy|Select|Selector)|Default[ _.-]*(Proxy|Select|Selector)|Outbound|Route[ _.-]*(Select|Selector))([^A-Za-z0-9]|$)}"
GROUP_EXCLUDE_RE="${HEAL_GROUP_EXCLUDE_REGEX:-广告|拦截|REJECT|DIRECT|直连|微软|Microsoft|苹果|Apple|谷歌|Google|FCM|电报|Telegram|Netflix|NETFLIX|Disney|YouTube|TikTok|媒体|Media|人工智能|(^|[^A-Za-z0-9])AI([^A-Za-z0-9]|$)|漏网|Final|MATCH}"
PROBE_URL="${HEAL_PROBE_URL:-${HEAL_TEST_URL:-https://cp.cloudflare.com/generate_204}}"
REGION_RE="${HEAL_ROUTE_REGION_REGEX:-${HEAL_US_REGEX:-}}"
CANDIDATE_RE="${HEAL_CANDIDATE_ROUTE_REGEX:-.}"
CANDIDATE_EXCLUDE_RE="${HEAL_CANDIDATE_EXCLUDE_REGEX:-^(DIRECT|REJECT)$|广告|广告拦截|Ad[ _.-]*(Block|Reject)|Ads?[ _.-]*(Block|Reject)}"
PREFERRED_RE="${HEAL_PREFERRED_ROUTE_REGEX:-}"
ROLE_GROUPS_ENABLED="${HEAL_ROLE_GROUPS_ENABLED:-1}"
ROLE_AD_GROUP_RE="${HEAL_ROLE_AD_BLOCK_GROUP_REGEX:-广告|广告拦截|Ad[ _.-]*(Block|Reject)|Ads?[ _.-]*(Block|Reject)|Reject}"
ROLE_AD_TARGET="${HEAL_ROLE_AD_BLOCK_TARGET:-REJECT}"
ROLE_ROUTE_GROUP_RE="${HEAL_ROLE_ROUTE_GROUP_MATCH_REGEX:-${HEAL_ROLE_US_GROUP_MATCH_REGEX:-}}"
ROLE_ROUTE_TARGET_RE="${HEAL_ROLE_ROUTE_TARGET_REGEX:-${HEAL_ROLE_US_TARGET_REGEX:-}}"
DELAY_PROBES="${HEAL_DELAY_PROBES:-2}"
DELAY_TIMEOUT_MS="${HEAL_DELAY_TIMEOUT_MS:-3000}"
MUTATE_NESTED_GROUPS="${HEAL_MUTATE_NESTED_GROUPS:-0}"
DRY_RUN="${HEAL_DRY_RUN:-1}"
VERIFY_ONLY="${HEAL_VERIFY_ONLY:-0}"
OBSERVE_ONLY="${HEAL_OBSERVE_ONLY:-0}"
LOG="${HEAL_LOG_OVERRIDE:-${HEAL_LOG:-/tmp/self-heal.log}}"
API_CACHE="${HEAL_API_CACHE:-/tmp/self-heal.api}"
STATE_DIR="${HEAL_STATE_DIR:-/tmp/home-edge-bootstrap}"
SWITCH_JOURNAL="$STATE_DIR/self-heal-switches.log"
MAX_SWITCHES_PER_HOUR="${HEAL_MAX_SWITCHES_PER_HOUR:-6}"
LOCK_DIR="${HEAL_LOCK_DIR:-/tmp/home-edge-bootstrap-write.lock}"
LOCK_STALE_SEC="${HEAL_LOCK_STALE_SEC:-1800}"
WRITE_LOCK_ALREADY_HELD="${HOME_EDGE_WRITE_LOCK_HELD:-0}"
LOG_MAX_BYTES="${HEAL_LOG_MAX_BYTES:-262144}"
ALLOW_REMOTE_API="${HEAL_ALLOW_REMOTE_API:-0}"
lock_held=0
auth_config=""

case "$DELAY_PROBES" in
  ""|*[!0-9]*|0) DELAY_PROBES=2 ;;
esac
case "$DELAY_TIMEOUT_MS" in
  ""|*[!0-9]*|0) DELAY_TIMEOUT_MS=3000 ;;
esac

log() {
  if [ "$OBSERVE_ONLY" = "1" ] || [ "$VERIFY_ONLY" = "1" ]; then
    echo "self-heal: $*" >&2
  else
    echo "$(date '+%F %T') self-heal: $*" >> "$LOG"
  fi
}
enc() { printf %s "$1" | jq -sRr @uri; }

validate_bool() {
  name="$1"
  value="$2"
  case "$value" in
    0|1) ;;
    *) log "ERROR invalid boolean $name=$value; expected 0 or 1"; exit 2 ;;
  esac
}
validate_bool HEAL_DRY_RUN "$DRY_RUN"
validate_bool HEAL_VERIFY_ONLY "$VERIFY_ONLY"
validate_bool HEAL_OBSERVE_ONLY "$OBSERVE_ONLY"
validate_bool HEAL_MUTATE_NESTED_GROUPS "$MUTATE_NESTED_GROUPS"
validate_bool HEAL_ROLE_GROUPS_ENABLED "$ROLE_GROUPS_ENABLED"
validate_bool HOME_EDGE_WRITE_LOCK_HELD "$WRITE_LOCK_ALREADY_HELD"
validate_bool HEAL_ALLOW_REMOTE_API "$ALLOW_REMOTE_API"

case "$MAX_SWITCHES_PER_HOUR" in ""|*[!0-9]*) MAX_SWITCHES_PER_HOUR=6 ;; esac

cleanup_runtime() {
  case "$auth_config" in ""|-) ;; *) rm -f "$auth_config" 2>/dev/null || true ;; esac
  if [ "$lock_held" = "1" ]; then
    rm -f "$LOCK_DIR/started_at" "$LOCK_DIR/pid" "$LOCK_DIR/operation" 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

rotate_log() {
  case "$LOG_MAX_BYTES" in ""|*[!0-9]*|0) LOG_MAX_BYTES=262144 ;; esac
  [ -f "$LOG" ] || return 0
  log_bytes=$(wc -c <"$LOG" 2>/dev/null | tr -d ' ')
  case "$log_bytes" in ""|*[!0-9]*) log_bytes=0 ;; esac
  [ "$log_bytes" -le "$LOG_MAX_BYTES" ] || mv -f "$LOG" "$LOG.1"
}

handle_signal() {
  cleanup_runtime
  trap - EXIT
  exit 130
}

acquire_lock() {
  [ "$WRITE_LOCK_ALREADY_HELD" != "1" ] || { log "INFO inherited global write lock"; return 0; }
  [ -n "$LOCK_DIR" ] && [ "$LOCK_DIR" != "/" ] || { log "ERROR invalid self-heal lock directory"; return 1; }
  case "$LOCK_DIR" in /tmp/?*) ;; *) log "ERROR self-heal lock must remain below /tmp"; return 1 ;; esac
  case "$LOCK_DIR" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) log "ERROR unsafe self-heal lock directory"; return 1 ;; esac
  case "$LOCK_STALE_SEC" in ""|*[!0-9]*|0) LOCK_STALE_SEC=1800 ;; esac
  mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || { log "ERROR cannot prepare self-heal lock parent"; return 1; }

  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    owner_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      operation=$(cat "$LOCK_DIR/operation" 2>/dev/null || echo unknown)
      log "SKIP global write lock held by pid=$owner_pid operation=$operation"
      return 2
    fi
    started=$(cat "$LOCK_DIR/started_at" 2>/dev/null || true)
    now=$(date +%s)
    case "$started:$now" in *[!0-9:]*|:*|*:) age=0 ;; *) age=$((now - started)) ;; esac
    if [ -z "$owner_pid" ] && [ "$age" -le "$LOCK_STALE_SEC" ]; then
      log "SKIP global write lock has no verifiable owner and lease has not expired"
      return 2
    fi
    rm -f "$LOCK_DIR/started_at" "$LOCK_DIR/pid" "$LOCK_DIR/operation" 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || { log "ERROR stale global write lock could not be cleared"; return 1; }
    mkdir "$LOCK_DIR" 2>/dev/null || { log "SKIP global write lock was reacquired by another process"; return 2; }
    log "INFO recovered stale global write lock"
  fi

  lock_held=1
  date +%s >"$LOCK_DIR/started_at" || return 1
  printf '%s\n' "$$" >"$LOCK_DIR/pid" || return 1
  printf '%s\n' self-heal >"$LOCK_DIR/operation" || return 1
}

capi_url() {
  if [ -z "$auth_config" ]; then
    curl -fsS --connect-timeout 1 --max-time 4 "$@"
    return $?
  fi
  if [ "$auth_config" = "-" ]; then
    printf 'header = "Authorization: Bearer %s"\n' "$SECRET" |
      curl -fsS --connect-timeout 1 --max-time 4 --config - "$@"
    return $?
  fi
  curl -fsS --connect-timeout 1 --max-time 4 --config "$auth_config" "$@"
}

loopback_ipv4() {
  host=$1
  case "$host" in
    *[!0-9.]*|*.*.*.*.*|.*|*.) return 1 ;;
  esac
  old_ifs=$IFS
  IFS=.
  set -- $host
  IFS=$old_ifs
  [ "$#" -eq 4 ] || return 1
  for octet in "$@"; do
    case "$octet" in ""|*[!0-9]*) return 1 ;; esac
    [ "$octet" -le 255 ] || return 1
  done
  [ "$1" -eq 127 ]
}

api_endpoint_allowed() {
  candidate="${1%/}"
  case "$candidate" in http://*|https://*) ;; *) return 1 ;; esac
  authority=${candidate#*://}
  authority=${authority%%/*}
  case "$authority" in
    ""|*@*) return 1 ;;
    localhost|localhost:*|"[::1]"|"[::1]":*) return 0 ;;
    \[*\]*) [ "$ALLOW_REMOTE_API" = "1" ]; return $? ;;
  esac
  host=${authority%%:*}
  loopback_ipv4 "$host" && return 0
  [ "$ALLOW_REMOTE_API" = "1" ]
}

prepare_auth_config() {
  [ -n "$SECRET" ] || return 0
  secret_newlines=$(printf '%s' "$SECRET" | wc -l | tr -d ' ')
  if [ "$secret_newlines" != "0" ] || printf '%s' "$SECRET" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    log "ERROR CLASH_SECRET contains unsupported control characters"
    return 1
  fi
  if printf '%s' "$SECRET" | LC_ALL=C grep -q '[\\"]'; then
    log "ERROR CLASH_SECRET contains unsupported quote or escape characters"
    return 1
  fi
  if [ "$OBSERVE_ONLY" = "1" ] || [ "$VERIFY_ONLY" = "1" ]; then
    auth_config=-
    return 0
  fi
  auth_config=$(mktemp /tmp/home-edge-curl-auth.XXXXXX) || { log "ERROR cannot allocate curl auth config"; return 1; }
  chmod 600 "$auth_config" 2>/dev/null || true
  printf 'header = "Authorization: Bearer %s"\n' "$SECRET" >"$auth_config" || return 1
}

api_alive() {
  u="${1%/}"
  api_endpoint_allowed "$u" || return 1
  r=$(capi_url "$u/version" 2>/dev/null)
  echo "$r" | jq -e 'type == "object"' >/dev/null 2>&1 && { echo "$u"; return 0; }
  r=$(capi_url "$u/proxies" 2>/dev/null)
  echo "$r" | jq -e '.proxies? | type == "object"' >/dev/null 2>&1 && { echo "$u"; return 0; }
  return 1
}

config_endpoint() {
  f="$1"
  [ -r "$f" ] || return 0
  v=$(grep -m1 '^[[:space:]]*external-controller:' "$f" 2>/dev/null \
    | sed 's/^[^:]*:[[:space:]]*//' \
    | sed "s/[\"']//g" \
    | tr -d '\r')
  [ -n "$v" ] || return 0

  case "$v" in
    http://*|https://*) echo "$v" ;;
    :*) echo "http://127.0.0.1$v" ;;
    0.0.0.0:*|localhost:*|127.0.0.1:*) echo "http://$v" | sed 's#0.0.0.0#127.0.0.1#' ;;
    *:*) echo "http://$v" ;;
    [0-9]*) echo "http://127.0.0.1:$v" ;;
  esac
}

discover_api() {
  [ -n "$API" ] && api_alive "$API" && return 0
  [ -r "$API_CACHE" ] && api_alive "$(cat "$API_CACHE" 2>/dev/null)" && return 0

  for f in \
    /etc/ShellClash/config.yaml \
    /etc/ShellClash/config.yml \
    /jffs/ShellClash/config.yaml \
    /jffs/ShellCrash/config.yaml \
    /jffs/ShellCrash/config.yml \
    /jffs/ShellCrash/yamls/config.yaml \
    /jffs/ShellCrash/yamls/config.yml \
    /jffs/shellclash/config.yaml \
    /tmp/ShellClash/config.yaml \
    /tmp/shellclash/config.yaml \
    /etc/clash/config.yaml \
    /tmp/clash/config.yaml \
    /jffs/clash/config.yaml
  do
    u=$(config_endpoint "$f")
    [ -n "$u" ] && api_alive "$u" && return 0
  done

  for u in \
    http://127.0.0.1:9090 \
    http://127.0.0.1:9999 \
    http://127.0.0.1:9097 \
    http://127.0.0.1:9091 \
    http://127.0.0.1:9098 \
    http://127.0.0.1:10090 \
    http://127.0.0.1:19090
  do
    api_alive "$u" && return 0
  done

  return 1
}

observe_failed_controller() {
  seen_status=""
  for u in \
    "${CLASH_API:-}" \
    "$(cat "$API_CACHE" 2>/dev/null || true)" \
    http://127.0.0.1:9090 \
    http://127.0.0.1:9999 \
    http://127.0.0.1:9097 \
    http://127.0.0.1:9091 \
    http://127.0.0.1:9098 \
    http://127.0.0.1:10090 \
    http://127.0.0.1:19090
  do
    u=${u%/}
    [ -n "$u" ] || continue
    api_endpoint_allowed "$u" || continue
    case " $seen_status " in *" $u "*) continue ;; esac
    seen_status="$seen_status $u"
    code=$(curl -sS --connect-timeout 1 --max-time 4 -o /dev/null -w '%{http_code}' "$u/version" 2>/dev/null || true)
    case "$code" in
      401|403)
        echo "controller_state=reachable"
        echo "controller_auth_state=required_or_failed"
        echo "controller_observation_state=blocked"
        return 0
        ;;
      2??)
        echo "controller_state=reachable"
        echo "controller_auth_state=unknown"
        echo "controller_observation_state=invalid_response"
        return 0
        ;;
    esac
  done
  echo "controller_state=unreachable"
  echo "controller_auth_state=unknown"
  echo "controller_observation_state=blocked"
}

trap cleanup_runtime EXIT
trap handle_signal HUP INT TERM
if [ "$OBSERVE_ONLY" != "1" ] && [ "$VERIFY_ONLY" != "1" ]; then
  if acquire_lock; then
    :
  else
    lock_status=$?
    [ "$lock_status" -eq 2 ] && exit 0
    exit 1
  fi
  rotate_log
fi
prepare_auth_config || exit 1

API="$(discover_api || true)"
if [ -z "$API" ]; then
  [ "$OBSERVE_ONLY" != "1" ] || observe_failed_controller
  log "ERROR: clash API auto-discovery failed; set CLASH_API=http://127.0.0.1:<port>"
  exit 1
fi
if [ "$OBSERVE_ONLY" != "1" ] && [ "$VERIFY_ONLY" != "1" ]; then
  if printf '%s\n' "$API" >"$API_CACHE" 2>/dev/null; then
    chmod 600 "$API_CACHE" 2>/dev/null || true
  else
    log "WARN cannot update API cache: $API_CACHE"
  fi
fi

if [ "$OBSERVE_ONLY" = "1" ]; then
  echo "controller_state=reachable"
  if [ -n "$SECRET" ]; then
    anonymous_code=$(curl -sS --connect-timeout 1 --max-time 4 -o /dev/null -w '%{http_code}' "$API/version" 2>/dev/null || true)
    case "$anonymous_code" in
      401|403) echo "controller_auth_state=authenticated" ;;
      2??) echo "controller_auth_state=unexpectedly_open" ;;
      *) echo "controller_auth_state=unknown" ;;
    esac
  else
    echo "controller_auth_state=not_required"
  fi
  dashboard_json=$(capi_url "$API/configs" 2>/dev/null || true)
  if printf '%s\n' "$dashboard_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
    if printf '%s\n' "$dashboard_json" | grep -Eq '"external-ui"[[:space:]]*:[[:space:]]*"[^"[:space:]][^"]*"'; then
      echo "dashboard_config_state=configured"
    else
      echo "dashboard_config_state=not_configured"
    fi
  else
    echo "dashboard_config_state=unknown"
  fi
  echo "controller_observation_state=ready"
  exit 0
fi

capi() { capi_url "$@"; }

matches() {
  pattern="$1"
  value="$2"
  [ -n "$pattern" ] && printf '%s\n' "$value" | grep -Eiq "$pattern"
}

matches_preferred() { matches "$PREFERRED_RE" "$1"; }

make_tmp_file() {
  prefix="${1:-home-edge}"
  t=$(mktemp "/tmp/${prefix}.XXXXXX" 2>/dev/null || true)
  [ -n "$t" ] || return 1
  printf '%s\n' "$t"
}

resolve_group() {
  proxies_json=$(capi "$API/proxies")
  [ -n "$proxies_json" ] || return 1

  if [ -n "$GROUP" ]; then
    printf '%s\n' "$proxies_json" \
      | jq -e --arg group "$GROUP" '.proxies[$group].all? | type == "array"' >/dev/null 2>&1 && {
        printf '%s\n' "$GROUP"
        return 0
      }

    found=$(printf '%s\n' "$proxies_json" \
      | jq -r --arg term "$GROUP" '
          .proxies
          | to_entries[]
          | select((.value.all? | type) == "array")
          | select(.key == $term or (.key | contains($term)))
          | .key
        ' 2>/dev/null \
      | head -1)
    [ -n "$found" ] && { printf '%s\n' "$found"; return 0; }
  fi

  found=$(printf '%s\n' "$proxies_json" \
    | jq -r --arg match "$GROUP_MATCH_RE" --arg exclude "$GROUP_EXCLUDE_RE" '
        .proxies as $p
        | [
            $p
            | to_entries[]
            | select((.value.all? | type) == "array")
            | . as $e
            | ($p | to_entries | map(select((.value.now // "") == $e.key)) | length) as $refs
            | ($match != "" and ($e.key | test($match; "i"))) as $namehit
            | ($exclude != "" and ($e.key | test($exclude; "i"))) as $excluded
            | {
                key: $e.key,
                score:
                  ((if $namehit then 0 else 200 end)
                  + (if (($e.value.type // "") == "Selector") then 0 else 80 end)
                  + (if $refs > 0 then 10 else 40 end)
                  + (if $excluded then 200 else 0 end)
                  + (if $e.key == "GLOBAL" then 250 else 0 end))
              }
          ]
        | sort_by(.score, .key)
        | .[0].key // empty
      ' 2>/dev/null \
    | head -1)
  [ -n "$found" ] && { printf '%s\n' "$found"; return 0; }

  return 1
}

# delay() <node-name> -> prints the worst successful latency ms across repeated probes.
# Empty means no probe reached PROBE_URL. Taking the worst successful value favors stable routes
# over a node that wins one lucky probe and then jitters.
delay() {
  probe_i=0
  worst=""
  while [ "$probe_i" -lt "$DELAY_PROBES" ]; do
    d=$(capi "$API/proxies/$(enc "$1")/delay?timeout=$DELAY_TIMEOUT_MS&url=$(enc "$PROBE_URL")" \
      | jq -r '.delay // empty' 2>/dev/null)
    case "$d" in
      ""|*[!0-9]*) ;;
      *)
        if [ -z "$worst" ] || [ "$d" -gt "$worst" ]; then
          worst="$d"
        fi
        ;;
    esac
    probe_i=$((probe_i + 1))
  done
  printf '%s\n' "$worst"
}

route_matches_region() {
  n="$1"
  [ -z "$REGION_RE" ] && return 0
  matches "$REGION_RE" "$n" && return 0
  ng=$(capi "$API/proxies/$(enc "$n")")
  nnow=$(echo "$ng" | jq -r '.now // empty' 2>/dev/null)
  [ -n "$nnow" ] && matches "$REGION_RE" "$nnow"
}

candidate_allowed() {
  candidate="$1"
  matches "$CANDIDATE_RE" "$candidate" || return 1
  if [ -n "$CANDIDATE_EXCLUDE_RE" ] && matches "$CANDIDATE_EXCLUDE_RE" "$candidate"; then
    return 1
  fi
  route_matches_region "$candidate"
}

add_candidate() {
  candidate_allowed "$1" || return 0
  d=$(delay "$1")
  prio=1
  matches_preferred "$1" && prio=0
  if [ -n "$d" ]; then
    score=$((prio * 1000000 + d))
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$score" "$prio" "$d" "$1" "" "" >> "$tmp"
  fi
}

add_nested_candidates() {
  [ "$MUTATE_NESTED_GROUPS" = "1" ] || return 0
  parent="$1"
  pg=$(capi "$API/proxies/$(enc "$parent")")
  echo "$pg" | jq -e '.all? | type == "array"' >/dev/null 2>&1 || return 0
  prio=2
  [ -n "$REGION_RE" ] && route_matches_region "$parent" && prio=1
  matches_preferred "$parent" && prio=0
  echo "$pg" | jq -r '.all[]' | while IFS= read -r child; do
    candidate_allowed "$child" || continue
    d=$(delay "$child")
    if [ -n "$d" ]; then
      score=$((prio * 1000000 + d))
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$score" "$prio" "$d" "$parent" "$parent" "$child" >> "$tmp"
    fi
  done
}

switch_group() {
  target_group="$1"
  target_node="$2"
  payload=$(printf '%s' "$target_node" | jq -Rs '{name:.}')
  capi -X PUT "$API/proxies/$(enc "$target_group")" -d "$payload" >/dev/null || return 1
  applied=$(capi "$API/proxies/$(enc "$target_group")" | jq -r '.now // empty' 2>/dev/null)
  [ "$applied" = "$target_node" ]
}

switch_allowed() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  chmod 700 "$STATE_DIR" 2>/dev/null || true
  now=$(date +%s)
  cutoff=$((now - 3600))
  recent=0

  if [ -r "$SWITCH_JOURNAL" ]; then
    tmpj=$(make_tmp_file home-edge-switches) || return 1
    while IFS= read -r line; do
      ts=${line%% *}
      case "$ts" in
        *[!0-9]*|"") continue ;;
      esac
      if [ "$ts" -ge "$cutoff" ]; then
        echo "$line" >> "$tmpj"
        recent=$((recent + 1))
      fi
    done < "$SWITCH_JOURNAL"
    mv "$tmpj" "$SWITCH_JOURNAL" 2>/dev/null || rm -f "$tmpj"
  fi

  [ "$recent" -lt "$MAX_SWITCHES_PER_HOUR" ]
}

record_switch() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  chmod 700 "$STATE_DIR" 2>/dev/null || true
  printf '%s %s -> %s\n' "$(date +%s)" "$1" "$2" >> "$SWITCH_JOURNAL" 2>/dev/null || true
}

choose_exact_role_target() {
  role_group="$1"
  wanted="$2"
  capi "$API/proxies/$(enc "$role_group")" \
    | jq -r '.all[]' 2>/dev/null \
    | while IFS= read -r candidate; do
        [ "$candidate" = "$wanted" ] && { printf '%s\n' "$candidate"; break; }
      done \
    | head -1
}

choose_route_role_target() {
  role_group="$1"
  [ -n "$ROLE_ROUTE_TARGET_RE" ] || return 0
  role_tmp=$(make_tmp_file home-edge-role-candidates) || return 1
  capi "$API/proxies/$(enc "$role_group")" \
    | jq -r '.all[]' 2>/dev/null \
    | while IFS= read -r candidate; do
        matches "$ROLE_ROUTE_TARGET_RE" "$candidate" || continue
        candidate_delay=$(delay "$candidate")
        [ -n "$candidate_delay" ] || continue
        score=$candidate_delay
        printf '%s\t%s\n' "$score" "$candidate" >>"$role_tmp"
      done
  target=$(sort -n "$role_tmp" | head -1 | cut -f2-)
  rm -f "$role_tmp"
  printf '%s\n' "$target"
}

enforce_role_group() {
  role_kind="$1"
  role_group="$2"
  target=""
  case "$role_kind" in
    ad) target=$(choose_exact_role_target "$role_group" "$ROLE_AD_TARGET") ;;
    route) target=$(choose_route_role_target "$role_group") ;;
  esac

  if [ -z "$target" ]; then
    log "WARN role group $role_group has no safe $role_kind target; left unchanged"
    return 0
  fi

  role_payload=$(capi "$API/proxies/$(enc "$role_group")")
  current=$(printf '%s\n' "$role_payload" | jq -r '.now // empty' 2>/dev/null)
  [ "$current" = "$target" ] && return 0

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN would switch role group $role_group: $current -> $target"
    return 0
  fi

  if ! switch_allowed; then
    log "CIRCUIT-BREAKER switch limit reached (${MAX_SWITCHES_PER_HOUR}/hour); left role group $role_group unchanged"
    return 0
  fi

  if switch_group "$role_group" "$target"; then
    record_switch "$current" "$target"
    log "SWITCHED role group $role_group: $current -> $target"
    return 0
  fi
  log "ERROR role switch failed or was not applied $role_group -> $target"
  return 1
}

enforce_role_groups() {
  [ "$ROLE_GROUPS_ENABLED" = "1" ] || return 0
  role_groups_tmp=$(make_tmp_file home-edge-role-groups) || return 1
  role_json=$(capi "$API/proxies") || { rm -f "$role_groups_tmp"; return 1; }
  printf '%s\n' "$role_json" \
    | jq -r '.proxies | to_entries[] | select((.value.all? | type) == "array" and ((.value.type // "") | test("(?i)^selector$|^select$"))) | .key' 2>/dev/null \
    >"$role_groups_tmp" || { rm -f "$role_groups_tmp"; return 1; }
  while IFS= read -r role_group; do
    [ "$role_group" = "$GROUP" ] && continue
    if matches "$ROLE_AD_GROUP_RE" "$role_group"; then
      enforce_role_group ad "$role_group" || { rm -f "$role_groups_tmp"; return 1; }
    elif [ -n "$ROLE_ROUTE_GROUP_RE" ] && [ -n "$ROLE_ROUTE_TARGET_RE" ] && matches "$ROLE_ROUTE_GROUP_RE" "$role_group"; then
      enforce_role_group route "$role_group" || { rm -f "$role_groups_tmp"; return 1; }
    fi
  done <"$role_groups_tmp"
  rm -f "$role_groups_tmp"
}

resolved=$(resolve_group || true)
[ -n "$resolved" ] || {
  groups=$(capi "$API/proxies" | jq -r '.proxies | keys[]' 2>/dev/null | head -20 | tr '\n' ',' | sed 's/,$//')
  log "ERROR no selectable main proxy group found at $API; set HEAL_GROUP explicitly. visible_groups=$groups"
  exit 1
}
if [ -z "$GROUP" ]; then
  log "INFO auto-discovered selector group '$resolved'"
elif [ "$resolved" != "$GROUP" ]; then
  log "INFO resolved group '$GROUP' -> '$resolved'"
fi
GROUP="$resolved"

g=$(capi "$API/proxies/$(enc "$GROUP")")
[ -n "$g" ] || { log "ERROR: clash API unreachable at $API"; exit 1; }
if ! echo "$g" | jq -e '.all? | type == "array"' >/dev/null 2>&1; then
  groups=$(capi "$API/proxies" | jq -r '.proxies | keys[]' 2>/dev/null | head -20 | tr '\n' ',' | sed 's/,$//')
  log "ERROR group '$GROUP' not found or is not selectable at $API; set HEAL_GROUP. visible_groups=$groups"
  exit 1
fi
cur=$(echo "$g" | jq -r '.now // empty')

if [ "$VERIFY_ONLY" = "1" ]; then
  route_probe_id="$(date +%s)-$$"
  echo "route_probe_id=$route_probe_id"
  echo "route_identity=$cur"
  if [ -n "$cur" ] && [ -n "$(delay "$cur")" ] && route_matches_region "$cur"; then
    if [ -n "$REGION_RE" ]; then
      echo "route_classification=region_match"
      echo "route_region_constraint=matched"
    else
      echo "route_classification=reachable"
      echo "route_region_constraint=none"
    fi
    log "VERIFY current=$cur reaches probe target; no mutation"
    echo "verification_state=pass"
    exit 0
  fi
  if [ -n "$REGION_RE" ]; then echo "route_region_constraint=not_matched"; else echo "route_region_constraint=none"; fi
  if [ -n "$cur" ]; then echo "route_classification=unreachable_or_region_mismatch"; else echo "route_classification=unknown"; fi
  log "ERROR verify-only current=$cur cannot reach probe target or satisfy the configured region constraint"
  echo "verification_state=fail"
  exit 1
fi

# 1) Preserve a reachable current route when it satisfies the optional region constraint.
if [ -n "$cur" ] && [ -n "$(delay "$cur")" ] && route_matches_region "$cur"; then
  log "OK current=$cur reaches probe target; no change"
  enforce_role_groups || exit 1
  exit 0
fi

# 2) Otherwise pick the best reachable eligible route. Nested mutation remains opt-in.
tmp=$(make_tmp_file home-edge-candidates) || { log "ERROR cannot create temp file"; exit 1; }
echo "$g" | jq -r '.all[]' | while IFS= read -r n; do
  add_candidate "$n"
  add_nested_candidates "$n"
done
bestline=$(sort -n "$tmp" | head -1)
rm -f "$tmp"

bestprio=$(printf '%s\n' "$bestline" | cut -f2)
bestd=$(printf '%s\n' "$bestline" | cut -f3)
best=$(printf '%s\n' "$bestline" | cut -f4)
child_group=$(printf '%s\n' "$bestline" | cut -f5)
child=$(printf '%s\n' "$bestline" | cut -f6)

if [ -z "$best" ]; then
  log "WARN no eligible route reached probe target (current=$cur); left unchanged"
  enforce_role_groups || exit 1
  exit 0
fi

if [ "$best" = "$cur" ] && [ -z "$child" ]; then
  log "OK current=$cur is the best available eligible route (${bestd}ms priority=$bestprio); no switch"
  enforce_role_groups || exit 1
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  if [ -n "$child" ]; then
    log "DRY-RUN would switch nested $child_group -> $child, then $GROUP: $cur -> $best (${bestd}ms priority=$bestprio)"
  else
    log "DRY-RUN would switch $GROUP: $cur -> $best (${bestd}ms priority=$bestprio)"
  fi
else
  if ! switch_allowed; then
    log "CIRCUIT-BREAKER switch limit reached (${MAX_SWITCHES_PER_HOUR}/hour); left $GROUP unchanged"
    enforce_role_groups
    exit 0
  fi
  child_previous=""
  if [ -n "$child" ]; then
    child_previous=$(capi "$API/proxies/$(enc "$child_group")" | jq -r '.now // empty' 2>/dev/null)
    switch_group "$child_group" "$child" || { log "ERROR nested switch failed or was not applied $child_group -> $child"; exit 1; }
  fi
  if switch_group "$GROUP" "$best"; then
    record_switch "$cur" "$best"
    log "SWITCHED $GROUP: $cur -> $best (${bestd}ms priority=$bestprio)"
  else
    if [ -n "$child" ] && [ -n "$child_previous" ]; then
      if switch_group "$child_group" "$child_previous"; then
        log "ROLLBACK nested $child_group: $child -> $child_previous"
      else
        log "ERROR nested rollback failed $child_group -> $child_previous"
      fi
    fi
    log "ERROR switch failed or was not applied $GROUP -> $best"
    exit 1
  fi
fi
enforce_role_groups || exit 1
