#!/bin/sh
# Offline behavior tests for check-client-topology.sh.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

fail() {
  echo "client_topology_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

state_from() {
  key="$1"
  input="$2"
  printf '%s\n' "$input" | awk -F= -v key="$key" '$1 == key { value=$0; sub("^[^=]*=", "", value); print value; exit }'
}

run_case() {
  name="$1"
  expected_mode="$2"
  expected_runtime="$3"
  expected_risk="$4"
  gateway="$5"
  proxy="$6"
  tun="$7"
  dns="$8"

  output=$(
    CLIENT_TOPOLOGY_FIXTURE_OS=linux \
    CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY="$gateway" \
    CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE="$proxy" \
    CLIENT_TOPOLOGY_FIXTURE_TUN_STATE="$tun" \
    CLIENT_TOPOLOGY_FIXTURE_DNS_STATE="$dns" \
    CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE=ok:204 \
    sh "$repo/scripts/check-client-topology.sh" user@192.168.50.1
  )

  mode=$(state_from client_topology_mode "$output")
  runtime=$(state_from client_runtime_present "$output")
  risk=$(state_from client_conflict_risk "$output")
  tun_state=$(state_from local_tun_state "$output")

  [ "$mode" = "$expected_mode" ] || fail "$name expected mode=$expected_mode got=$mode"
  [ "$runtime" = "$expected_runtime" ] || fail "$name expected runtime=$expected_runtime got=$runtime"
  [ "$risk" = "$expected_risk" ] || fail "$name expected risk=$expected_risk got=$risk"
  [ "$tun_state" = "$tun" ] || fail "$name expected local_tun_state=$tun got=$tun_state"
}

run_route_case() {
  name="$1"
  default_route="$2"
  effective_route="$3"
  expected_tun="$4"
  expected_runtime="$5"
  expected_mode="$6"

  output=$(
    CLIENT_TOPOLOGY_FIXTURE_OS=linux \
    CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY=192.168.50.1 \
    CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE=none \
    CLIENT_TOPOLOGY_FIXTURE_DNS_STATE=ordinary:142.250.0.1 \
    CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE=ok:204 \
    CLIENT_TOPOLOGY_FIXTURE_DEFAULT_ROUTE="$default_route" \
    CLIENT_TOPOLOGY_FIXTURE_EFFECTIVE_ROUTE="$effective_route" \
    sh "$repo/scripts/check-client-topology.sh" user@192.168.50.1
  )

  tun_state=$(state_from local_tun_state "$output")
  runtime=$(state_from client_runtime_present "$output")
  mode=$(state_from client_topology_mode "$output")
  [ "$tun_state" = "$expected_tun" ] || fail "$name expected local_tun_state=$expected_tun got=$tun_state"
  [ "$runtime" = "$expected_runtime" ] || fail "$name expected runtime=$expected_runtime got=$runtime"
  [ "$mode" = "$expected_mode" ] || fail "$name expected mode=$expected_mode got=$mode"
}

run_case router_primary router_primary 0 low 192.168.50.1 none absent ordinary:142.250.0.1
run_case hybrid hybrid 1 medium 192.168.50.1 none present fake_ip:198.18.0.2
run_case client_fallback client_fallback 1 low 192.168.99.1 env_proxy absent ordinary:142.250.0.1
run_case not_using_router not_using_router 0 medium 192.168.99.1 none absent ordinary:142.250.0.1
run_case pac_proxy hybrid 1 medium 192.168.50.1 pac_proxy absent ordinary:142.250.0.1
run_case fake_ip_without_visible_route hybrid 1 medium 192.168.50.1 none unknown fake_ip:198.18.0.2
run_case unnamed_path_interceptor hybrid 1 medium 192.168.50.1 none present ordinary:142.250.0.1
run_case inspection_unknown unknown unknown unknown 192.168.50.1 unknown unknown unknown
run_case overlay_not_on_path router_primary 0 low 192.168.50.1 none absent ordinary:142.250.0.1
run_route_case route_owned_by_unnamed_interceptor '192.168.50.1|eth0' '0.0.0.0|edge0' present 1 hybrid
run_route_case unrelated_overlay_route '192.168.50.1|eth0' '192.168.50.1|eth0' absent 0 router_primary

if grep -Eiq 'flclash|tailscale|zerotier|hiddify' \
  "$repo/scripts/check-client-topology.ps1" \
  "$repo/scripts/check-client-topology.sh"; then
  fail "client topology detectors still classify through product names"
fi

echo "client_topology_fixture_tests=ok"
