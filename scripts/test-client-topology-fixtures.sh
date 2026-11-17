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
  router_dns="$9"
  expected_fake_ip_owner="${10}"

  output=$(
    CLIENT_TOPOLOGY_FIXTURE_OS=linux \
    CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY="$gateway" \
    CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE="$proxy" \
    CLIENT_TOPOLOGY_FIXTURE_TUN_STATE="$tun" \
    CLIENT_TOPOLOGY_FIXTURE_DNS_STATE="$dns" \
    CLIENT_TOPOLOGY_FIXTURE_ROUTER_DNS_STATE="$router_dns" \
    CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE=ok:204 \
    sh "$repo/scripts/check-client-topology.sh" user@192.168.50.1
  )

  mode=$(state_from client_topology_mode "$output")
  runtime=$(state_from client_runtime_present "$output")
  risk=$(state_from client_conflict_risk "$output")
  tun_state=$(state_from local_tun_state "$output")
  fake_ip_owner=$(state_from fake_ip_owner "$output")

  [ "$mode" = "$expected_mode" ] || fail "$name expected mode=$expected_mode got=$mode"
  [ "$runtime" = "$expected_runtime" ] || fail "$name expected runtime=$expected_runtime got=$runtime"
  [ "$risk" = "$expected_risk" ] || fail "$name expected risk=$expected_risk got=$risk"
  [ "$tun_state" = "$tun" ] || fail "$name expected local_tun_state=$tun got=$tun_state"
  [ "$fake_ip_owner" = "$expected_fake_ip_owner" ] || fail "$name expected fake_ip_owner=$expected_fake_ip_owner got=$fake_ip_owner"
  if [ "$gateway" = "unknown" ]; then
    gateway_match=$(state_from gateway_matches_router "$output")
    [ "$gateway_match" = unknown ] || fail "$name expected gateway_matches_router=unknown got=$gateway_match"
  fi
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
    CLIENT_TOPOLOGY_FIXTURE_ROUTER_DNS_STATE=ordinary:142.250.0.1 \
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

# Load only real detector functions; each inspector test runs in an isolated
# subshell and exposes only mocked commands to capability discovery.
load_detector_functions() {
  eval "$(awk '/^os_state=\$\(detect_os\)/ { exit } { print }' "$repo/scripts/check-client-topology.sh")"
}

test_missing_proxy_inspector() (
  load_detector_functions
  unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
  unset CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE
  CLIENT_TOPOLOGY_FIXTURE_OS=linux
  command() { return 1; }
  actual=$(proxy_state)
  [ "$actual" = unknown ] || fail "missing_linux_proxy_inspector expected unknown got=$actual"
)

test_windows_gateway_dispatch() (
  load_detector_functions
  unset CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY
  CLIENT_TOPOLOGY_FIXTURE_OS=windows
  mock_dir=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-topology-command.XXXXXX")
  trap 'rm -f "$mock_dir/powershell.exe"; rmdir "$mock_dir"' EXIT HUP INT TERM
  printf '#!/bin/sh\nprintf "192.168.50.1\\n"\n' >"$mock_dir/powershell.exe"
  chmod +x "$mock_dir/powershell.exe"
  PATH="$mock_dir:$PATH"
  command() {
    case "$1:$2" in
      -v:route|-v:powershell.exe) printf '%s\n' "$2" ;;
      *) return 1 ;;
    esac
  }
  route() { return 1; } # Windows route.exe rejects Unix route arguments.
  actual=$(default_gateway)
  [ "$actual" = 192.168.50.1 ] || fail "windows_gateway_dispatch expected 192.168.50.1 got=${actual:-empty}"
)

test_posix_gateway_dispatch() (
  load_detector_functions
  unset CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY
  command() { [ "$1:$2" = '-v:route' ]; }
  route() {
    case "$CLIENT_TOPOLOGY_FIXTURE_OS:$*" in
      'linux:-n') printf '0.0.0.0 192.168.50.1 0.0.0.0 UG 0 0 0 eth0\n' ;;
      'macos:-n get default') printf 'gateway: 192.168.50.1\n' ;;
      *) return 1 ;;
    esac
  }
  for CLIENT_TOPOLOGY_FIXTURE_OS in linux macos; do
    actual=$(default_gateway)
    [ "$actual" = 192.168.50.1 ] || fail "$CLIENT_TOPOLOGY_FIXTURE_OS gateway dispatch returned ${actual:-empty}"
  done
)

test_linux_ip_gateway() (
  load_detector_functions
  unset CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY
  CLIENT_TOPOLOGY_FIXTURE_OS=linux
  command() { [ "$1:$2" = '-v:ip' ]; }
  ip() { printf '%s\n' "$route_line"; }
  route_line='default via 192.168.50.1 dev eth0'
  actual=$(default_gateway)
  [ "$actual" = 192.168.50.1 ] || fail "linux_ip_via expected router gateway got=${actual:-empty}"
  route_line='default dev tun0 scope link'
  actual=$(default_gateway)
  [ -z "$actual" ] || fail "linux_ip_on_link expected unknown gateway got=$actual"
  route_line='default dev tun0 scope link
default via 192.168.50.1 dev eth0 metric 100'
  actual=$(default_gateway)
  [ -z "$actual" ] || fail "linux_ip_on_link_then_gateway expected unknown gateway got=$actual"
)

test_wget_probe() (
  load_detector_functions
  unset CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE
  command() { [ "$1:$2" = '-v:wget' ]; }
  wget() { [ "$probe_case" = success ]; }
  for probe_case in success failure; do
    expected=fail
    [ "$probe_case" != success ] || expected=ok
    actual=$(http_probe)
    [ "$actual" = "$expected" ] || fail "wget_$probe_case expected $expected got=$actual"
  done
)

test_nslookup_answers() (
  load_detector_functions
  unset CLIENT_TOPOLOGY_FIXTURE_DNS_STATE CLIENT_TOPOLOGY_FIXTURE_ROUTER_DNS_STATE
  command() {
    case "$1:$2" in -v:nslookup) printf 'nslookup\n' ;; *) return 1 ;; esac
  }
  nslookup() {
    printf 'Server: 192.168.50.1\nAddress: 192.168.50.1#53\n\n'
    case "$dns_case" in
      nxdomain) printf '** server cannot find sample.example: NXDOMAIN\n'; return 1 ;;
      timeout) printf ';; connection timed out; no servers could be reached\n'; return 1 ;;
      resolver_header_only) return 0 ;;
      malformed_answer) printf 'Name: sample.example\nAddress: 999.184.215.14\n' ;;
      ordinary_answer) printf 'Non-authoritative answer:\nName: sample.example\nAddress: 93.184.215.14\n' ;;
    esac
  }
  for dns_case in nxdomain timeout resolver_header_only malformed_answer ordinary_answer; do
    expected=unknown
    [ "$dns_case" != ordinary_answer ] || expected=ordinary:93.184.215.14
    actual=$(dns_state sample.example)
    [ "$actual" = "$expected" ] || fail "nslookup_$dns_case client expected $expected got=$actual"
    actual=$(router_dns_state sample.example 192.168.50.1)
    [ "$actual" = "$expected" ] || fail "nslookup_$dns_case router expected $expected got=$actual"
  done
)

test_missing_proxy_inspector
test_windows_gateway_dispatch
test_posix_gateway_dispatch
test_linux_ip_gateway
test_nslookup_answers
test_wget_probe

run_case router_primary router_primary 0 low 192.168.50.1 none absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
run_case hybrid hybrid 1 medium 192.168.50.1 none present fake_ip:198.18.0.2 fake_ip:198.18.0.2 router
run_case client_fallback client_fallback 1 low 192.168.99.1 env_proxy absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
run_case persistent_user_proxy hybrid 1 medium 192.168.50.1 user_env_proxy absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
run_case not_using_router not_using_router 0 medium 192.168.99.1 none absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
run_case pac_proxy hybrid 1 medium 192.168.50.1 pac_proxy absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
run_case fake_ip_without_visible_route hybrid 1 medium 192.168.50.1 none unknown fake_ip:198.18.0.2 ordinary:142.250.0.1 client
run_case router_fake_ip_without_client_runtime router_primary 0 low 192.168.50.1 none absent fake_ip:28.0.0.42 fake_ip:28.0.0.42 router
run_case unattributed_fake_ip unknown unknown unknown 192.168.50.1 none absent fake_ip:28.0.0.42 unknown unknown
run_case unnamed_path_interceptor hybrid 1 medium 192.168.50.1 none present ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
run_case inspection_unknown unknown unknown unknown 192.168.50.1 unknown unknown unknown unknown not_applicable
run_case overlay_not_on_path router_primary 0 low 192.168.50.1 none absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
run_case unknown_gateway_without_proxy unknown 0 unknown unknown none absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
run_case unknown_gateway_with_proxy unknown 1 unknown unknown env_proxy absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
run_route_case route_owned_by_unnamed_interceptor '192.168.50.1|eth0' '0.0.0.0|edge0' present 1 hybrid
run_route_case benchmark_default_interceptor '198.18.0.2|edge0' '198.18.0.2|edge0' present 1 hybrid
run_route_case unrelated_overlay_route '192.168.50.1|eth0' '192.168.50.1|eth0' absent 0 router_primary

if grep -Eiq 'flclash|tailscale|zerotier|hiddify' \
  "$repo/scripts/check-client-topology.ps1" \
  "$repo/scripts/check-client-topology.sh"; then
  fail "client topology detectors still classify through product names"
fi
for detector in \
  "$repo/scripts/check-client-topology.ps1" \
  "$repo/scripts/check-client-topology.sh"; do
  grep -Fq 'HKCU:\Environment' "$detector" ||
    fail "$detector does not inspect persistent Windows proxy environment"
done

echo "client_topology_fixture_tests=ok"
