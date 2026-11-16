#!/bin/sh
# Sourced by the generic runner. No firewall or network setting is changed.
# Unknown transparent-proxy topologies deliberately stay observe-only/unbound.
home_edge_service_probe_preflight() {
  service_preflight_config=$1
  service_preflight_bridge=$2
  service_preflight_stage=$3
  unset HOME_EDGE_SERVICE_PROBE_BYPASS_MARK HOME_EDGE_SERVICE_PROBE_IPV6_BYPASS
  [ -r "$service_preflight_config" ] || return 1
  "$service_preflight_bridge" decode "$service_preflight_config" "$service_preflight_stage/preflight.json" 2>/dev/null || return 1
  service_ipv6=$("$JQ_BIN" -r '.ipv6 // false' "$service_preflight_stage/preflight.json") || return 1
  case "$service_ipv6" in true|false) ;; *) return 1 ;; esac
  service_mark=$("$JQ_BIN" -r '."routing-mark" // empty' "$service_preflight_stage/preflight.json") || return 1
  case "$service_mark" in ''|*[!0-9]*|0) return 1 ;; esac
  [ "$service_mark" -le 2147483647 ] 2>/dev/null || return 1
  # This initial reference adapter supports verified router-originated bypass:
  # both OUTPUT chains have no rules and accept. Do not infer bypass merely from
  # a RETURN in some unrelated PREROUTING chain. Other topologies need an adapter.
  which iptables >/dev/null 2>&1 || return 1
  which nft >/dev/null 2>&1 && return 1
  for service_table in nat mangle; do
    service_output=$(iptables -t "$service_table" -S OUTPUT 2>/dev/null) || return 1
    [ "$service_output" = '-P OUTPUT ACCEPT' ] || return 1
  done
  if [ "$service_ipv6" = true ]; then
    which ip6tables >/dev/null 2>&1 || return 1
    for service_table in nat mangle; do
      service_output=$(ip6tables -t "$service_table" -S OUTPUT 2>/dev/null) || return 1
      [ "$service_output" = '-P OUTPUT ACCEPT' ] || return 1
    done
    HOME_EDGE_SERVICE_PROBE_IPV6_BYPASS=verified
    export HOME_EDGE_SERVICE_PROBE_IPV6_BYPASS
  fi
  HOME_EDGE_SERVICE_PROBE_BYPASS_MARK=$service_mark
  export HOME_EDGE_SERVICE_PROBE_BYPASS_MARK
  return 0
}
