#!/bin/sh
# Offline behavior tests for self-heal.sh using a fake Mihomo API.
set -u

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-self-heal-test.XXXXXX") || exit 1
router_tmp_root=$(mktemp -d "/tmp/home-edge-self-heal-router-test.XXXXXX") || { rm -rf "$tmp_root"; exit 1; }
export HEAL_LOCK_DIR="$router_tmp_root/write.lock"
fake_bin="$tmp_root/bin"
mkdir -p "$fake_bin"

cleanup() {
  case "$tmp_root" in */home-edge-self-heal-test.*) rm -rf "$tmp_root" ;; esac
  case "$router_tmp_root" in /tmp/home-edge-self-heal-router-test.*) rm -rf "$router_tmp_root" ;; esac
}
trap cleanup EXIT HUP INT TERM

cat >"$fake_bin/curl" <<'EOF'
#!/bin/sh
method=GET
data=""
url=""
writeout=""
has_auth=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -X)
      shift
      method="${1:-GET}"
      ;;
    -d)
      shift
      data="${1:-}"
      ;;
    -w|--write-out)
      shift
      writeout="${1:-}"
      ;;
    -o|--output)
      shift
      ;;
    --config)
      has_auth=1
      ;;
    http://*|https://*)
      url="$1"
      ;;
  esac
  shift || break
done

[ -z "${SELF_HEAL_CURL_LOG:-}" ] || printf '%s\n' "$url" >>"$SELF_HEAL_CURL_LOG"

fixture="${SELF_HEAL_FIXTURE:-main_select}"
case "$url" in
  http://*/*) path="/${url#http://*/}" ;;
  https://*/*) path="/${url#https://*/}" ;;
  *) path="$url" ;;
esac

if [ "$path" = "/version" ] && [ "$has_auth" = "0" ] && [ -n "${SELF_HEAL_ANON_STATUS:-}" ]; then
  if [ -n "$writeout" ]; then printf '%s' "$SELF_HEAL_ANON_STATUS"; exit 0; fi
  case "$SELF_HEAL_ANON_STATUS" in 2??) printf '{"meta":true,"version":"fixture"}\n'; exit 0 ;; *) exit 22 ;; esac
fi

if [ "${SELF_HEAL_FORCE_UNAUTHORIZED:-0}" = "1" ]; then
  if [ -n "$writeout" ]; then printf '401'; exit 0; fi
  exit 22
fi
if [ "${SELF_HEAL_FORCE_UNREACHABLE:-0}" = "1" ]; then
  if [ -n "$writeout" ]; then printf '000'; exit 0; fi
  exit 7
fi

put_was_applied() {
  [ "${SELF_HEAL_PUT_NO_APPLY:-0}" != "1" ] || return 1
  grep -Fq "PUT $1 " "${SELF_HEAL_PUT_LOG:-/tmp/home-edge-self-heal-put.log}" 2>/dev/null
}

if [ "$method" = "PUT" ]; then
  if [ "${SELF_HEAL_PUT_FAIL:-0}" = "1" ]; then
    printf '%s %s %s\n' "$method" "$path" "$data" >>"${SELF_HEAL_PUT_LOG:-/tmp/home-edge-self-heal-put.log}"
    exit 7
  fi
  printf '%s %s %s\n' "$method" "$path" "$data" >>"${SELF_HEAL_PUT_LOG:-/tmp/home-edge-self-heal-put.log}"
  printf '{}\n'
  exit 0
fi

case "$path" in
  /version)
    if [ "$fixture" = "malformed_api" ]; then
      printf 'not-json\n'
      exit 0
    fi
    printf '{"meta":true,"version":"fixture"}\n'
    exit 0
    ;;
  /configs)
    if [ "${SELF_HEAL_CONFIGS_INVALID:-0}" = "1" ]; then
      printf 'not-json\n'
    elif [ "${SELF_HEAL_DASHBOARD_CONFIGURED:-0}" = "1" ]; then
      printf '{"external-ui":"/etc/mihomo/ui"}\n'
    else
      printf '{}\n'
    fi
    exit 0
    ;;
  /proxies)
    case "$fixture" in
      malformed_api)
        printf 'not-json\n'
        ;;
      no_selectable)
        cat <<'JSON'
{"proxies":{"DIRECT":{"type":"Direct"},"REJECT":{"type":"Reject"}}}
JSON
        ;;
      role_missing_targets)
        cat <<'JSON'
{"proxies":{"Main Select":{"type":"Selector","now":"USA - Los Angeles","all":["USA - Los Angeles","DIRECT"]},"USA - Los Angeles":{"type":"Http"},"Ad Block":{"type":"Selector","now":"DIRECT","all":["DIRECT"]},"Microsoft Services":{"type":"Selector","now":"DIRECT","all":["DIRECT","Hong Kong"]},"Hong Kong":{"type":"Http"},"DIRECT":{"type":"Direct"}}}
JSON
        ;;
      nested_us)
        cat <<'JSON'
{"proxies":{"Main Select":{"type":"Selector","now":"Japan Tokyo","all":["Japan Tokyo","US Auto","DIRECT"]},"US Auto":{"type":"Selector","now":"Hong Kong","all":["Hong Kong","USA - Los Angeles"]},"Japan Tokyo":{"type":"Http"},"Hong Kong":{"type":"Http"},"USA - Los Angeles":{"type":"Http"},"DIRECT":{"type":"Direct"}}}
JSON
        ;;
      role_drift)
        cat <<'JSON'
{"proxies":{"Main Select":{"type":"Selector","now":"USA - Los Angeles","all":["USA - Los Angeles","DIRECT"]},"USA - Los Angeles":{"type":"Http"},"Ad Block":{"type":"Selector","now":"DIRECT","all":["DIRECT","REJECT"]},"Microsoft Services":{"type":"Selector","now":"DIRECT","all":["DIRECT","US Auto","Hong Kong"]},"US Auto":{"type":"URLTest","now":"USA - Los Angeles","all":["USA - Los Angeles"]},"US-Auto-AI":{"type":"URLTest","now":"USA - Los Angeles","all":["USA - Los Angeles"]},"Hong Kong":{"type":"Http"},"DIRECT":{"type":"Direct"},"REJECT":{"type":"Reject"}}}
JSON
        ;;
      current_us)
        cat <<'JSON'
{"proxies":{"Main Select":{"type":"Selector","now":"USA - Los Angeles","all":["Japan Tokyo","USA - Los Angeles","DIRECT"]},"Japan Tokyo":{"type":"Http"},"USA - Los Angeles":{"type":"Http"},"DIRECT":{"type":"Direct"}}}
JSON
        ;;
      no_us)
        cat <<'JSON'
{"proxies":{"Main Select":{"type":"Selector","now":"Japan Tokyo","all":["Japan Tokyo","Singapore","DIRECT"]},"Japan Tokyo":{"type":"Http"},"Singapore":{"type":"Http"},"DIRECT":{"type":"Direct"}}}
JSON
        ;;
      *)
        cat <<'JSON'
{"proxies":{"Main Select":{"type":"Selector","now":"Japan Tokyo","all":["Japan Tokyo","United States - New York","DIRECT","Ad Block"]},"Japan Tokyo":{"type":"Http"},"United States - New York":{"type":"Http"},"DIRECT":{"type":"Direct"},"Ad Block":{"type":"Selector","now":"REJECT","all":["DIRECT","REJECT"]},"REJECT":{"type":"Reject"}}}
JSON
        ;;
    esac
    exit 0
    ;;
  /proxies/Main%20Select)
    case "$fixture" in
      nested_us)
        printf '{"type":"Selector","now":"Japan Tokyo","all":["Japan Tokyo","US Auto","DIRECT"]}\n'
        ;;
      role_missing_targets)
        printf '{"type":"Selector","now":"USA - Los Angeles","all":["USA - Los Angeles","DIRECT"]}\n'
        ;;
      role_drift)
        printf '{"type":"Selector","now":"USA - Los Angeles","all":["USA - Los Angeles","DIRECT"]}\n'
        ;;
      current_us)
        printf '{"type":"Selector","now":"USA - Los Angeles","all":["Japan Tokyo","USA - Los Angeles","DIRECT"]}\n'
        ;;
      no_us)
        printf '{"type":"Selector","now":"Japan Tokyo","all":["Japan Tokyo","Singapore","DIRECT"]}\n'
        ;;
      *)
        if put_was_applied /proxies/Main%20Select; then
          printf '{"type":"Selector","now":"United States - New York","all":["Japan Tokyo","United States - New York","DIRECT","Ad Block"]}\n'
        else
          printf '{"type":"Selector","now":"Japan Tokyo","all":["Japan Tokyo","United States - New York","DIRECT","Ad Block"]}\n'
        fi
        ;;
    esac
    exit 0
    ;;
  /proxies/Ad%20Block)
    case "$fixture" in
      role_missing_targets)
        printf '{"type":"Selector","now":"DIRECT","all":["DIRECT"]}\n'
        ;;
      *)
        if put_was_applied /proxies/Ad%20Block; then
          printf '{"type":"Selector","now":"REJECT","all":["DIRECT","REJECT"]}\n'
        else
          printf '{"type":"Selector","now":"DIRECT","all":["DIRECT","REJECT"]}\n'
        fi
        ;;
    esac
    exit 0
    ;;
  /proxies/Microsoft%20Services)
    case "$fixture" in
      role_missing_targets)
        printf '{"type":"Selector","now":"DIRECT","all":["DIRECT","Hong Kong"]}\n'
        ;;
      *)
        if put_was_applied /proxies/Microsoft%20Services; then
          printf '{"type":"Selector","now":"US Auto","all":["DIRECT","US Auto","Hong Kong"]}\n'
        else
          printf '{"type":"Selector","now":"DIRECT","all":["DIRECT","US Auto","Hong Kong"]}\n'
        fi
        ;;
    esac
    exit 0
    ;;
  /proxies/US%20Auto)
    case "$fixture" in
      nested_us)
        if put_was_applied /proxies/US%20Auto; then
          printf '{"type":"Selector","now":"USA - Los Angeles","all":["Hong Kong","USA - Los Angeles"]}\n'
        else
          printf '{"type":"Selector","now":"Hong Kong","all":["Hong Kong","USA - Los Angeles"]}\n'
        fi
        ;;
      *)
        printf '{"type":"URLTest","now":"USA - Los Angeles","all":["USA - Los Angeles"]}\n'
        ;;
    esac
    exit 0
    ;;
  /proxies/Hong%20Kong)
    printf '{"type":"Http"}\n'
    exit 0
    ;;
  /proxies/Japan%20Tokyo)
    printf '{"type":"Http"}\n'
    exit 0
    ;;
  /proxies/United%20States%20-%20New%20York)
    printf '{"type":"Http"}\n'
    exit 0
    ;;
  /proxies/USA%20-%20Los%20Angeles)
    printf '{"type":"Http"}\n'
    exit 0
    ;;
  /proxies/Singapore)
    printf '{"type":"Http"}\n'
    exit 0
    ;;
  /proxies/Japan%20Tokyo/delay*)
    [ "$fixture" = "no_us" ] && { printf '{}\n'; exit 0; }
    printf '{"delay":80}\n'
    exit 0
    ;;
  /proxies/United%20States%20-%20New%20York/delay*)
    printf '{"delay":120}\n'
    exit 0
    ;;
  /proxies/USA%20-%20Los%20Angeles/delay*)
    printf '{"delay":140}\n'
    exit 0
    ;;
  /proxies/Singapore/delay*)
    printf '{"delay":90}\n'
    exit 0
    ;;
  /proxies/US%20Auto/delay*)
    [ "$fixture" = "nested_us" ] && { printf '{}\n'; exit 0; }
    printf '{"delay":130}\n'
    exit 0
    ;;
esac

printf '{}\n'
EOF
chmod 755 "$fake_bin/curl"

cat >"$fake_bin/jq" <<'EOF'
#!/bin/sh
filter=""
group=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --arg)
      shift
      name="${1:-}"
      shift
      value="${1:-}"
      [ "$name" = "group" ] && group="$value"
      ;;
    -*)
      ;;
    *)
      filter="$filter $1"
      ;;
  esac
  shift || break
done

input=$(cat)
fixture="${SELF_HEAL_FIXTURE:-main_select}"

case "$filter" in
  *"@uri"*)
    printf '%s' "$input" | sed 's/ /%20/g'
    exit 0
    ;;
  *'type == "object"'*)
    case "$input" in
      \{*) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  *'.proxies[$group].all?'*)
    case "$fixture:$group" in
      no_selectable:*) exit 1 ;;
      *:"Main Select"|*:"Ad Block"|*:"Microsoft Services"|*:"US Auto") exit 0 ;;
    esac
    exit 1
    ;;
  *'.all? | type == "array"'*)
    case "$input" in
      *'"all":['*) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  *'sort_by(.score, .key)'*)
    [ "$fixture" = "no_selectable" ] && exit 0
    printf 'Main Select\n'
    exit 0
    ;;
  *'.all[]'*)
    case "$input" in
      *'"all":["DIRECT"]'*)
        printf 'DIRECT\n'
        ;;
      *'"all":["DIRECT","REJECT"]'*)
        printf 'DIRECT\nREJECT\n'
        ;;
      *'"all":["DIRECT","US Auto","Hong Kong"]'*)
        printf 'DIRECT\nUS Auto\nHong Kong\n'
        ;;
      *'"all":["DIRECT","Hong Kong"]'*)
        printf 'DIRECT\nHong Kong\n'
        ;;
      *'"all":["Japan Tokyo","US Auto","DIRECT"]'*)
        printf 'Japan Tokyo\nUS Auto\nDIRECT\n'
        ;;
      *'"all":["Hong Kong","USA - Los Angeles"]'*)
        printf 'Hong Kong\nUSA - Los Angeles\n'
        ;;
      *'"all":["USA - Los Angeles"]'*)
        printf 'USA - Los Angeles\n'
        ;;
      *)
        case "$fixture" in
          role_drift)
            printf 'USA - Los Angeles\nDIRECT\n'
            ;;
          current_us)
            printf 'Japan Tokyo\nUSA - Los Angeles\nDIRECT\n'
            ;;
          no_us)
            printf 'Japan Tokyo\nSingapore\nDIRECT\n'
            ;;
          *)
            printf 'Japan Tokyo\nUnited States - New York\nDIRECT\nAd Block\n'
            ;;
        esac
        ;;
    esac
    exit 0
    ;;
  *'.delay // empty'*)
    printf '%s\n' "$input" | sed -n 's/.*"delay":[[:space:]]*\([0-9][0-9]*\).*/\1/p'
    exit 0
    ;;
  *'.now // empty'*)
    printf '%s\n' "$input" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p'
    exit 0
    ;;
  *'{name:.}'*)
    printf '{"name":"%s"}\n' "$input"
    exit 0
    ;;
  *'.proxies | to_entries[]'*)
    case "$fixture" in
      no_selectable)
        ;;
      role_missing_targets)
        case "$filter" in
          *'test("(?i)^selector$|^select$")'*)
            printf 'Main Select\nAd Block\nMicrosoft Services\n'
            ;;
          *)
            printf 'Main Select\nAd Block\nMicrosoft Services\n'
            ;;
        esac
        ;;
      nested_us)
        case "$filter" in
          *'test("(?i)^selector$|^select$")'*)
            printf 'Main Select\nUS Auto\n'
            ;;
          *)
            printf 'Main Select\nUS Auto\n'
            ;;
        esac
        ;;
      role_drift)
        case "$filter" in
          *'test("(?i)^selector$|^select$")'*)
            printf 'Main Select\nAd Block\nMicrosoft Services\n'
            ;;
          *)
            printf 'Main Select\nAd Block\nMicrosoft Services\nUS Auto\nUS-Auto-AI\n'
            ;;
        esac
        ;;
      current_us|no_us)
        printf 'Main Select\n'
        ;;
      *)
        printf 'Main Select\nAd Block\n'
        ;;
    esac
    exit 0
    ;;
  *'.proxies | keys[]'*)
    [ "$fixture" = "no_selectable" ] && { printf 'DIRECT\nREJECT\n'; exit 0; }
    printf 'Main Select\nJapan Tokyo\nUnited States - New York\nDIRECT\n'
    exit 0
    ;;
esac

printf '%s\n' "$input"
EOF
chmod 755 "$fake_bin/jq"

cat >"$fake_bin/sort" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-n" ]; then
  shift
fi
cat "$@"
EOF
chmod 755 "$fake_bin/sort"

fail() {
  echo "self_heal_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

run_case() {
  fixture="$1"
  log_file="$tmp_root/$fixture.log"
  put_log="$tmp_root/$fixture.put.log"
  state_dir="$router_tmp_root/$fixture-state"
  api_cache="$tmp_root/$fixture.api"
  shift
  : >"$put_log"
  last_log="$log_file"

  PATH="$fake_bin:$PATH" \
  SELF_HEAL_FIXTURE="$fixture" \
  SELF_HEAL_PUT_LOG="$put_log" \
  CLASH_API="http://127.0.0.1:18080" \
  HEAL_LOG="$log_file" \
  HEAL_API_CACHE="$api_cache" \
  HEAL_STATE_DIR="$state_dir" \
  HEAL_DELAY_PROBES=1 \
  HEAL_DELAY_TIMEOUT_MS=1000 \
  "$@" sh "$repo/scripts/self-heal.sh" || {
    cat "$log_file" >&2 2>/dev/null || true
    fail "fixture $fixture exited non-zero"
  }
}

assert_log() {
  log_file="$1"
  expected="$2"
  grep -Fq "$expected" "$log_file" || {
    cat "$log_file" >&2
    fail "missing log text: $expected"
  }
}

assert_not_log() {
  log_file="$1"
  unexpected="$2"
  if grep -Fq "$unexpected" "$log_file"; then
    cat "$log_file" >&2
    fail "unexpected log text: $unexpected"
  fi
}

last_log=""
if [ "${1:-}" = "--verify-readonly-only" ]; then
  readonly_root="$tmp_root/verify-readonly"
  readonly_router_root="$router_tmp_root/verify-readonly"
  mkdir -p "$readonly_root/bin" "$readonly_router_root/lock"
  printf '%s\n' sentinel-log >"$readonly_root/self-heal.log"
  printf '%s\n' sentinel-api >"$readonly_root/self-heal.api"
  cp "$readonly_root/self-heal.log" "$readonly_root/log.before"
  cp "$readonly_root/self-heal.api" "$readonly_root/api.before"
  printf '%s\n' 999999 >"$readonly_router_root/lock/pid"
  date +%s >"$readonly_router_root/lock/started_at"
  printf '%s\n' sentinel-operation >"$readonly_router_root/lock/operation"
  cp -R "$readonly_router_root/lock" "$readonly_router_root/lock.before"
  real_mktemp=$(command -v mktemp)
  cat >"$readonly_root/bin/mktemp" <<EOF
#!/bin/sh
case "\${1:-}" in /tmp/home-edge-curl-auth.*) echo auth-temp-created >>"$readonly_root/mktemp.log"; exit 98 ;; esac
exec "$real_mktemp" "\$@"
EOF
  chmod 755 "$readonly_root/bin/mktemp"
  verify_readonly_output=$(PATH="$readonly_root/bin:$fake_bin:$PATH" SELF_HEAL_FIXTURE=current_us \
    CLASH_API=http://127.0.0.1:18080 CLASH_SECRET=readonly-secret HEAL_VERIFY_ONLY=1 \
    HEAL_LOG="$readonly_root/self-heal.log" HEAL_LOG_MAX_BYTES=1 HEAL_API_CACHE="$readonly_root/self-heal.api" \
    HEAL_LOCK_DIR="$readonly_router_root/lock" HEAL_STATE_DIR="$readonly_router_root/state" HEAL_DELAY_PROBES=1 \
    HEAL_ROLE_GROUPS_ENABLED=0 sh "$repo/scripts/self-heal.sh") || fail "verify-only read-only probe failed"
  printf '%s\n' "$verify_readonly_output" | grep -q '^verification_state=pass$' || fail "verify-only read-only evidence missing"
  cmp -s "$readonly_root/self-heal.log" "$readonly_root/log.before" || fail "verify-only mutated or rotated log"
  cmp -s "$readonly_root/self-heal.api" "$readonly_root/api.before" || fail "verify-only mutated API cache"
  diff -r "$readonly_router_root/lock" "$readonly_router_root/lock.before" >/dev/null || fail "verify-only mutated global lock"
  [ ! -e "$readonly_router_root/state" ] || fail "verify-only created state storage"
  [ ! -e "$readonly_root/mktemp.log" ] || fail "verify-only created auth temp file"
  if printf '%s\n' "$verify_readonly_output" | grep -Fq readonly-secret; then fail "verify-only leaked controller secret"; fi
  echo "self_heal_verify_readonly_fixture_tests=ok"
  exit 0
fi

run_case main_select env HEAL_DRY_RUN=1 HEAL_ROLE_GROUPS_ENABLED=0
assert_log "$last_log" "INFO auto-discovered selector group 'Main Select'"
assert_log "$last_log" "OK current=Japan Tokyo reaches probe target; no change"

run_case current_us env HEAL_DRY_RUN=1 HEAL_ROLE_GROUPS_ENABLED=0
assert_log "$last_log" "OK current=USA - Los Angeles reaches probe target; no change"

# Profiles without an ad-block selector are valid: capability absence is a no-op.
run_case current_us env HEAL_DRY_RUN=1
assert_log "$last_log" "OK current=USA - Los Angeles reaches probe target; no change"
assert_not_log "$last_log" "role group"

run_case no_us env HEAL_DRY_RUN=1 HEAL_ROLE_GROUPS_ENABLED=0
assert_log "$last_log" "DRY-RUN would switch Main Select: Japan Tokyo -> Singapore"

run_case main_select env HEAL_DRY_RUN=1 HEAL_ROLE_GROUPS_ENABLED=0 HEAL_ROUTE_REGION_REGEX='United States|USA'
assert_log "$last_log" "DRY-RUN would switch Main Select: Japan Tokyo -> United States - New York"

run_case role_drift env HEAL_DRY_RUN=1
assert_log "$last_log" "DRY-RUN would switch role group Ad Block: DIRECT -> REJECT"
assert_not_log "$last_log" "role group Microsoft Services"

run_case role_missing_targets env HEAL_DRY_RUN=1 HEAL_ROLE_ROUTE_GROUP_MATCH_REGEX='Microsoft' HEAL_ROLE_ROUTE_TARGET_REGEX='US Auto'
assert_log "$last_log" "WARN role group Ad Block has no safe ad target; left unchanged"
assert_log "$last_log" "WARN role group Microsoft Services has no safe route target; left unchanged"

run_case role_drift env HEAL_DRY_RUN=0 HEAL_ROLE_ROUTE_GROUP_MATCH_REGEX='Microsoft' HEAL_ROLE_ROUTE_TARGET_REGEX='US Auto'
assert_log "$last_log" "SWITCHED role group Ad Block: DIRECT -> REJECT"
assert_log "$last_log" "SWITCHED role group Microsoft Services: DIRECT -> US Auto"
grep -Fq '/proxies/Ad%20Block' "$tmp_root/role_drift.put.log" || fail "missing ad role PUT"
grep -Fq '/proxies/Microsoft%20Services' "$tmp_root/role_drift.put.log" || fail "missing Microsoft role PUT"
if grep -Fq '/proxies/US-Auto-AI' "$tmp_root/role_drift.put.log"; then
  fail "URLTest role-looking groups must not be mutated"
fi

run_case nested_us env HEAL_DRY_RUN=1 HEAL_MUTATE_NESTED_GROUPS=1 HEAL_ROLE_GROUPS_ENABLED=0 HEAL_ROUTE_REGION_REGEX='US|USA'
assert_log "$last_log" "DRY-RUN would switch nested US Auto -> USA - Los Angeles, then Main Select: Japan Tokyo -> US Auto"

verify_put_log="$tmp_root/verify-only.put.log"
: >"$verify_put_log"
verify_output=$(
  PATH="$fake_bin:$PATH" \
  SELF_HEAL_FIXTURE=current_us \
  SELF_HEAL_PUT_LOG="$verify_put_log" \
  CLASH_API="http://127.0.0.1:18080" \
  HEAL_LOG="$tmp_root/verify-only.log" \
  HEAL_API_CACHE="$tmp_root/verify-only.api" \
  HEAL_STATE_DIR="$router_tmp_root/verify-only-state" \
  HEAL_DELAY_PROBES=1 \
  HEAL_DELAY_TIMEOUT_MS=1000 \
  HEAL_VERIFY_ONLY=1 \
  HEAL_ROLE_GROUPS_ENABLED=1 \
  sh "$repo/scripts/self-heal.sh"
) || fail "verify-only probe should succeed for a reachable current route"
printf '%s\n' "$verify_output" | grep -q '^verification_state=pass$' || fail "verify-only pass marker missing"
printf '%s\n' "$verify_output" | grep -q '^route_identity=USA - Los Angeles$' || fail "verify-only route identity missing"
printf '%s\n' "$verify_output" | grep -q '^route_classification=reachable$' || fail "verify-only generic classification missing"
printf '%s\n' "$verify_output" | grep -q '^route_region_constraint=none$' || fail "verify-only region constraint evidence missing"
printf '%s\n' "$verify_output" | grep -Eq '^route_probe_id=[0-9]+-[0-9]+$' || fail "verify-only fresh probe ID missing"
[ ! -s "$verify_put_log" ] || fail "verify-only probe must never mutate selectors"

observe_put_log="$tmp_root/observe-only.put.log"
: >"$observe_put_log"
observe_output=$(
  PATH="$fake_bin:$PATH" \
  SELF_HEAL_FIXTURE=current_us \
  SELF_HEAL_ANON_STATUS=401 \
  SELF_HEAL_DASHBOARD_CONFIGURED=0 \
  SELF_HEAL_PUT_LOG="$observe_put_log" \
  CLASH_API="http://127.0.0.1:18080" \
  CLASH_SECRET=fixture-secret \
  HEAL_LOG="$tmp_root/observe-only.log" \
  HEAL_API_CACHE="$tmp_root/observe-only.api" \
  HEAL_STATE_DIR="$router_tmp_root/observe-only-state" \
  HEAL_OBSERVE_ONLY=1 \
  sh "$repo/scripts/self-heal.sh"
) || fail "observe-only probe should report authenticated controller state"
printf '%s\n' "$observe_output" | grep -q '^controller_state=reachable$' || fail "observe-only reachable state missing"
printf '%s\n' "$observe_output" | grep -q '^controller_auth_state=authenticated$' || fail "observe-only authenticated state missing"
printf '%s\n' "$observe_output" | grep -q '^dashboard_config_state=not_configured$' || fail "controller-observed dashboard absence missing"
printf '%s\n' "$observe_output" | grep -q '^controller_observation_state=ready$' || fail "observe-only ready state missing"
[ ! -s "$observe_put_log" ] || fail "observe-only probe must never mutate selectors"

open_with_secret_output=$(
  PATH="$fake_bin:$PATH" SELF_HEAL_FIXTURE=current_us SELF_HEAL_ANON_STATUS=200 \
  CLASH_API="http://127.0.0.1:18080" CLASH_SECRET='do-not-print-this-secret' \
  HEAL_OBSERVE_ONLY=1 sh "$repo/scripts/self-heal.sh"
) || fail "open controller with supplied secret should remain observable"
printf '%s\n' "$open_with_secret_output" | grep -q '^controller_auth_state=unexpectedly_open$' || fail "open controller with supplied secret was mislabeled authenticated"
if printf '%s\n' "$open_with_secret_output" | grep -Fq 'do-not-print-this-secret'; then fail "controller secret leaked"; fi

open_without_secret_output=$(
  PATH="$fake_bin:$PATH" SELF_HEAL_FIXTURE=current_us SELF_HEAL_ANON_STATUS=200 \
  CLASH_API="http://127.0.0.1:18080" HEAL_OBSERVE_ONLY=1 sh "$repo/scripts/self-heal.sh"
) || fail "open controller without secret should remain observable"
printf '%s\n' "$open_without_secret_output" | grep -q '^controller_auth_state=not_required$' || fail "no-secret open controller state missing"

dashboard_output=$(
  PATH="$fake_bin:$PATH" SELF_HEAL_FIXTURE=current_us SELF_HEAL_ANON_STATUS=401 SELF_HEAL_DASHBOARD_CONFIGURED=1 \
  CLASH_API="http://127.0.0.1:18080" CLASH_SECRET=fixture-secret HEAL_OBSERVE_ONLY=1 sh "$repo/scripts/self-heal.sh"
) || fail "controller dashboard observation failed"
printf '%s\n' "$dashboard_output" | grep -q '^dashboard_config_state=configured$' || fail "controller-observed alternate/generated dashboard config missing"

unknown_dashboard_output=$(
  PATH="$fake_bin:$PATH" SELF_HEAL_FIXTURE=current_us SELF_HEAL_ANON_STATUS=401 SELF_HEAL_CONFIGS_INVALID=1 \
  CLASH_API="http://127.0.0.1:18080" CLASH_SECRET=fixture-secret HEAL_OBSERVE_ONLY=1 sh "$repo/scripts/self-heal.sh"
) || fail "incomplete dashboard discovery should remain observable"
printf '%s\n' "$unknown_dashboard_output" | grep -q '^dashboard_config_state=unknown$' || fail "incomplete dashboard discovery was mislabeled not configured"

observe_readonly_root="$tmp_root/observe-readonly"
observe_readonly_router_root="$router_tmp_root/observe-readonly"
observe_readonly_bin="$observe_readonly_root/bin"
observe_readonly_log="$observe_readonly_root/sentinel.log"
observe_readonly_cache="$observe_readonly_root/sentinel.api"
observe_readonly_lock="$observe_readonly_router_root/write.lock"
mkdir -p "$observe_readonly_bin" "$observe_readonly_router_root"
printf '%s\n' 'sentinel-log-content' >"$observe_readonly_log"
printf '%s\n' 'sentinel-cache-content' >"$observe_readonly_cache"
cp "$observe_readonly_log" "$observe_readonly_root/log.before"
cp "$observe_readonly_cache" "$observe_readonly_root/cache.before"
cat >"$observe_readonly_bin/mktemp" <<'EOF'
#!/bin/sh
echo "observe-only unexpectedly called mktemp" >&2
exit 97
EOF
chmod 755 "$observe_readonly_bin/mktemp"
readonly_observe_output=$(
  PATH="$observe_readonly_bin:$fake_bin:$PATH" \
  SELF_HEAL_FIXTURE=current_us \
  CLASH_API="http://127.0.0.1:18080" \
  CLASH_SECRET="fixture-secret" \
  HEAL_LOG="$observe_readonly_log" \
  HEAL_LOG_MAX_BYTES=1 \
  HEAL_API_CACHE="$observe_readonly_cache" \
  HEAL_LOCK_DIR="$observe_readonly_lock" \
  HEAL_STATE_DIR="$observe_readonly_router_root/state" \
  HEAL_OBSERVE_ONLY=1 \
  sh "$repo/scripts/self-heal.sh"
) || fail "observe-only read-only sentinel probe failed"
printf '%s\n' "$readonly_observe_output" | grep -q '^controller_observation_state=ready$' || fail "observe-only read-only probe did not emit controller evidence"
cmp -s "$observe_readonly_log" "$observe_readonly_root/log.before" || fail "observe-only mutated or rotated the log sentinel"
cmp -s "$observe_readonly_cache" "$observe_readonly_root/cache.before" || fail "observe-only mutated the API-cache sentinel"
[ ! -e "$observe_readonly_log.1" ] || fail "observe-only created a rotated log"
[ ! -e "$observe_readonly_lock" ] || fail "observe-only acquired the global write lock"
[ ! -e "$observe_readonly_router_root/state" ] || fail "observe-only created state storage"

control_secret=$(printf 'SENSITIVEVALUE\rwith-tab\tend')
set +e
control_secret_output=$(
  PATH="$fake_bin:$PATH" \
  SELF_HEAL_FIXTURE=current_us \
  CLASH_API="http://127.0.0.1:18080" \
  CLASH_SECRET="$control_secret" \
  HEAL_LOG="$tmp_root/observe-control-secret.log" \
  HEAL_API_CACHE="$tmp_root/observe-control-secret.api" \
  HEAL_STATE_DIR="$router_tmp_root/observe-control-secret-state" \
  HEAL_OBSERVE_ONLY=1 \
  sh "$repo/scripts/self-heal.sh" 2>&1
)
control_secret_status=$?
set -e
[ "$control_secret_status" -ne 0 ] || fail "observe-only accepted control characters in CLASH_SECRET"
printf '%s\n' "$control_secret_output" | grep -q 'CLASH_SECRET contains unsupported control characters' || fail "control-character secret rejection message missing"
if printf '%s\n' "$control_secret_output" | grep -Fq 'SENSITIVEVALUE'; then
  fail "control-character secret leaked into output"
fi

unauthorized_output=$(
  PATH="$fake_bin:$PATH" \
  SELF_HEAL_FORCE_UNAUTHORIZED=1 \
  CLASH_API="http://127.0.0.1:18080" \
  CLASH_SECRET=wrong-secret \
  HEAL_LOG="$tmp_root/observe-unauthorized.log" \
  HEAL_API_CACHE="$tmp_root/observe-unauthorized.api" \
  HEAL_STATE_DIR="$router_tmp_root/observe-unauthorized-state" \
  HEAL_OBSERVE_ONLY=1 \
  sh "$repo/scripts/self-heal.sh" 2>/dev/null
) && fail "unauthorized observe-only probe should not pass"
printf '%s\n' "$unauthorized_output" | grep -q '^controller_state=reachable$' || fail "unauthorized controller reachability was not distinguished"
printf '%s\n' "$unauthorized_output" | grep -q '^controller_auth_state=required_or_failed$' || fail "unauthorized controller auth state missing"

unreachable_output=$(
  PATH="$fake_bin:$PATH" \
  SELF_HEAL_FORCE_UNREACHABLE=1 \
  CLASH_API="http://127.0.0.1:18080" \
  HEAL_LOG="$tmp_root/observe-unreachable.log" \
  HEAL_API_CACHE="$tmp_root/observe-unreachable.api" \
  HEAL_STATE_DIR="$router_tmp_root/observe-unreachable-state" \
  HEAL_OBSERVE_ONLY=1 \
  sh "$repo/scripts/self-heal.sh" 2>/dev/null
) && fail "unreachable observe-only probe should not pass"
printf '%s\n' "$unreachable_output" | grep -q '^controller_state=unreachable$' || fail "unreachable controller state missing"

put_failure_log="$tmp_root/main-put-failure.log"
if PATH="$fake_bin:$PATH" \
  SELF_HEAL_FIXTURE=main_select \
  SELF_HEAL_PUT_FAIL=1 \
  SELF_HEAL_PUT_LOG="$tmp_root/main-put-failure.put.log" \
  CLASH_API="http://127.0.0.1:18080" \
  HEAL_LOG="$put_failure_log" \
  HEAL_API_CACHE="$tmp_root/main-put-failure.api" \
  HEAL_STATE_DIR="$router_tmp_root/main-put-failure-state" \
  HEAL_DELAY_PROBES=1 \
  HEAL_DELAY_TIMEOUT_MS=1000 \
  HEAL_DRY_RUN=0 \
  HEAL_ROUTE_REGION_REGEX='United States|USA' \
  HEAL_ROLE_GROUPS_ENABLED=0 \
  sh "$repo/scripts/self-heal.sh"; then
  fail "main selector PUT failure should propagate a non-zero exit"
fi
assert_log "$put_failure_log" "ERROR switch failed or was not applied Main Select -> United States - New York"

run_case main_select env HEAL_DRY_RUN=0 HEAL_MAX_SWITCHES_PER_HOUR=0 HEAL_ROLE_GROUPS_ENABLED=0 HEAL_ROUTE_REGION_REGEX='United States|USA'
assert_log "$last_log" "CIRCUIT-BREAKER switch limit reached (0/hour); left Main Select unchanged"
if [ -s "$tmp_root/main_select.put.log" ]; then
  fail "circuit breaker should prevent PUT calls"
fi

if PATH="$fake_bin:$PATH" \
  SELF_HEAL_FIXTURE=no_selectable \
  CLASH_API="http://127.0.0.1:18080" \
  HEAL_LOG="$tmp_root/no_selectable.log" \
  HEAL_API_CACHE="$tmp_root/no_selectable.api" \
  HEAL_STATE_DIR="$router_tmp_root/no_selectable-state" \
  HEAL_ROLE_GROUPS_ENABLED=0 \
  sh "$repo/scripts/self-heal.sh" >/tmp/home-edge-self-heal-no-selectable.out 2>/tmp/home-edge-self-heal-no-selectable.err; then
  fail "no selectable proxy group should fail"
fi
assert_log "$tmp_root/no_selectable.log" "ERROR no selectable main proxy group found"

deceptive_api_curl_log="$tmp_root/deceptive-loopback.curl.log"
if ! PATH="$fake_bin:$PATH" \
  SELF_HEAL_FIXTURE=current_us \
  SELF_HEAL_CURL_LOG="$deceptive_api_curl_log" \
  CLASH_API="http://127.evil.example:18080" \
  HEAL_LOG="$tmp_root/deceptive-loopback.log" \
  HEAL_API_CACHE="$tmp_root/deceptive-loopback.api" \
  HEAL_STATE_DIR="$router_tmp_root/deceptive-loopback-state" \
  HEAL_VERIFY_ONLY=1 \
  HEAL_ROLE_GROUPS_ENABLED=0 \
  sh "$repo/scripts/self-heal.sh" >"$tmp_root/deceptive-loopback.out" 2>"$tmp_root/deceptive-loopback.err"; then
  fail "self-heal should continue with an allowed local API candidate"
fi
if grep -Fq 'http://127.evil.example:18080/' "$deceptive_api_curl_log"; then
  fail "deceptive loopback-looking API hostname should not be requested"
fi

if PATH="$fake_bin:$PATH" \
  SELF_HEAL_FIXTURE=malformed_api \
  CLASH_API="http://127.0.0.1:18080" \
  HEAL_LOG="$tmp_root/malformed_api.log" \
  HEAL_API_CACHE="$tmp_root/malformed_api.api" \
  HEAL_STATE_DIR="$router_tmp_root/malformed_api-state" \
  HEAL_ROLE_GROUPS_ENABLED=0 \
  sh "$repo/scripts/self-heal.sh" >/tmp/home-edge-self-heal-malformed.out 2>/tmp/home-edge-self-heal-malformed.err; then
  fail "malformed API discovery should fail"
fi
assert_log "$tmp_root/malformed_api.log" "ERROR: clash API auto-discovery failed"

echo "self_heal_fixture_tests=ok"
