#!/bin/sh
# Exercise wrapper lifecycle and adapter preconditions; Go tests cover semantics.
set -eu
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
jq_bin=${SERVICE_HEALTH_FIXTURE_JQ:-$(which jq 2>/dev/null || true)}
[ -x "$jq_bin" ] || { echo 'service_health_fixture=jq_required' >&2; exit 1; }
fixture=$(mktemp -d /tmp/home-edge-service-fixture.XXXXXX)
owned_pid=
cleanup() {
  if [ -n "$owned_pid" ]; then kill -TERM "$owned_pid" 2>/dev/null || true; wait "$owned_pid" 2>/dev/null || true; fi
  case "$fixture" in /tmp/home-edge-service-fixture.*) rm -rf "$fixture" ;; esac
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
mkdir "$fixture/bin" "$fixture/site"
cp "$repo/scripts/service-health.sh" "$fixture/run.sh"
cp "$repo/scripts/home-edge-secure-temp.sh" "$fixture/secure.sh"
cp "$repo/adapters/merlin/service-health-preflight.sh" "$fixture/preflight.sh"
cat >"$fixture/bridge" <<'EOF'
#!/bin/sh
set -eu
if [ "$1" = decode ]; then cp "$2" "$3"; exit 0; fi
if [ "$1" = service-health-validate ]; then
  [ "${FIXTURE_INVALID_REGISTRATION:-0}" != 1 ] || exit 1
  cp "$2" "$3"; exit 0
fi
[ "$1" = service-health ]
printf 'run\n' >>"$FIXTURE_ROOT/calls"
"$JQ_BIN" -r .mode "$2" >"$FIXTURE_ROOT/mode"
if [ "${FIXTURE_BLOCK:-0}" = 1 ]; then
  sleep 30 & sleeper=$!
  trap 'kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; echo stopped >"$FIXTURE_ROOT/stopped"; exit 130' TERM INT HUP
  echo ready >"$FIXTURE_ROOT/started"
  wait "$sleeper"
fi
printf '{"schema_version":1,"mode":"%s","verification_scope":"frontend_only","services":[]}' "$(cat "$FIXTURE_ROOT/mode")" >"$3"
EOF
cat >"$fixture/bin/which" <<'EOF'
#!/bin/sh
[ "$1" != nft ] || exit 1
exec /usr/bin/which "$@"
EOF
cat >"$fixture/bin/iptables" <<'EOF'
#!/bin/sh
printf '%s\n' '-P OUTPUT ACCEPT'
[ "${FIXTURE_INTERCEPT:-0}" != 1 ] || printf '%s\n' '-A OUTPUT -j REDIRECT'
EOF
cp "$fixture/bin/iptables" "$fixture/bin/ip6tables"
chmod 700 "$fixture/bridge" "$fixture/bin/which" "$fixture/bin/iptables" "$fixture/bin/ip6tables"
printf '{"routing-mark":7894,"ipv6":true}\n' >"$fixture/runtime.json"
printf '{"mode":"auto","runtime_config":"%s","core_path":"/fixture/core"}\n' "$fixture/runtime.json" >"$fixture/site/service-health.json"
export FIXTURE_ROOT=$fixture JQ_BIN=$jq_bin
export PATH="$fixture/bin:$PATH"
export HOME_EDGE_STATE_ROOT="$fixture/site"
export HOME_EDGE_YAMLBRIDGE_BIN="$fixture/bridge"
export HOME_EDGE_SERVICE_HEALTH_STATE_DIR="$fixture/state"
export HOME_EDGE_SECURE_TEMP_HELPER="$fixture/secure.sh"
export HOME_EDGE_SERVICE_HEALTH_PREFLIGHT="$fixture/preflight.sh"
export HOME_EDGE_WRITE_LOCK_DIR="$fixture/global.lock"
export SERVICE_HEALTH_PID_FILE="$fixture/absent.pid"
export SERVICE_HEALTH_POLICY_FILE="$fixture/no-policy"

# Actual adapter: no configuration/firewall write; both address families required.
. "$fixture/preflight.sh"
mkdir "$fixture/preflight-good"
HOME_EDGE_SERVICE_PROBE_BYPASS_MARK=stale
HOME_EDGE_SERVICE_PROBE_IPV6_BYPASS=stale
home_edge_service_probe_preflight "$fixture/runtime.json" "$fixture/bridge" "$fixture/preflight-good"
[ "$HOME_EDGE_SERVICE_PROBE_BYPASS_MARK" = 7894 ]
[ "$HOME_EDGE_SERVICE_PROBE_IPV6_BYPASS" = verified ]
mkdir "$fixture/preflight-bad"
FIXTURE_INTERCEPT=1; export FIXTURE_INTERCEPT
if home_edge_service_probe_preflight "$fixture/runtime.json" "$fixture/bridge" "$fixture/preflight-bad"; then exit 1; fi
[ -z "${HOME_EDGE_SERVICE_PROBE_BYPASS_MARK:-}" ]
[ -z "${HOME_EDGE_SERVICE_PROBE_IPV6_BYPASS:-}" ]
unset FIXTURE_INTERCEPT

# Reject the original registration before acquiring a write lock or probing.
if FIXTURE_INVALID_REGISTRATION=1 sh "$fixture/run.sh" --run >"$fixture/invalid.out" 2>&1; then exit 1; fi
grep -q invalid_registration "$fixture/invalid.out"
[ ! -e "$HOME_EDGE_WRITE_LOCK_DIR" ]
[ ! -e "$fixture/calls" ]

# Explicit check cannot inherit auto authority, and it never owns the writer lock.
sh "$fixture/run.sh" --check >"$fixture/check.out"
[ "$(cat "$fixture/mode")" = observe ]
[ ! -e "$HOME_EDGE_WRITE_LOCK_DIR" ]
mkdir "$HOME_EDGE_WRITE_LOCK_DIR"
echo foreign >"$HOME_EDGE_WRITE_LOCK_DIR/owner"
sh "$fixture/run.sh" --run >"$fixture/busy.out"
grep -q writer_busy "$fixture/busy.out"
[ "$(wc -l <"$fixture/calls" | tr -d ' ')" = 1 ]
rm "$HOME_EDGE_WRITE_LOCK_DIR/owner"; rmdir "$HOME_EDGE_WRITE_LOCK_DIR"

# The existing cron interval is bounded; a second scheduled call does not probe.
sh "$fixture/run.sh" --scheduled >"$fixture/scheduled.out"
sh "$fixture/run.sh" --scheduled >"$fixture/not-due.out"
grep -q not_due "$fixture/not-due.out"
[ "$(wc -l <"$fixture/calls" | tr -d ' ')" = 2 ]

# Kill wrapper while bridge is live: cleanup waits for child and preserves a
# replaced global lock rather than deleting the later writer's allocation.
FIXTURE_BLOCK=1; export FIXTURE_BLOCK
sh "$fixture/run.sh" --run >"$fixture/cancel.out" 2>&1 &
owned_pid=$!
i=0
while [ ! -f "$fixture/started" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i+1)); done
[ -f "$fixture/started" ]
case "$HOME_EDGE_WRITE_LOCK_DIR" in "$fixture"/*) rm -rf "$HOME_EDGE_WRITE_LOCK_DIR" ;; *) exit 1 ;; esac
mkdir "$HOME_EDGE_WRITE_LOCK_DIR"
echo later >"$HOME_EDGE_WRITE_LOCK_DIR/service-health.owner"
echo foreign >"$HOME_EDGE_WRITE_LOCK_DIR/pid"
echo other >"$HOME_EDGE_WRITE_LOCK_DIR/operation"
kill -TERM "$owned_pid"
wait "$owned_pid" 2>/dev/null || true
owned_pid=
[ -f "$fixture/stopped" ]
[ "$(cat "$HOME_EDGE_WRITE_LOCK_DIR/service-health.owner")" = later ]
echo 'service_health_fixture_tests=ok'
