#!/bin/sh
# Read-only local client topology diagnostic. It does not change proxy settings.
set -u

router="${1:-${ROUTER:-}}"
check_url="${CLIENT_CHECK_URL:-https://cp.cloudflare.com/generate_204}"

router_host() {
  value="$1"
  case "$value" in
    *@*) printf '%s\n' "${value##*@}" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

print_kv() {
  key="$1"
  value="$2"
  [ -n "$value" ] || value=unknown
  printf '%s=%s\n' "$key" "$value"
}

detect_os() {
  [ -n "${CLIENT_TOPOLOGY_FIXTURE_OS:-}" ] && { printf '%s\n' "$CLIENT_TOPOLOGY_FIXTURE_OS"; return; }
  uname_s=$(uname -s 2>/dev/null || printf unknown)
  case "$uname_s" in
    Darwin) printf macos ;;
    Linux) printf linux ;;
    MINGW*|MSYS*|CYGWIN*) printf windows ;;
    *) printf '%s\n' "$uname_s" | tr '[:upper:]' '[:lower:]' ;;
  esac
}

default_gateway() {
  [ -n "${CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY:-}" ] && { printf '%s\n' "$CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY"; return; }
  if command -v ip >/dev/null 2>&1; then
    ip route 2>/dev/null | awk '$1 == "default" { print $3; exit }'
    return
  fi
  if command -v route >/dev/null 2>&1; then
    route -n get default 2>/dev/null | awk '/gateway:/ { print $2; exit }'
    return
  fi
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1 -ExpandProperty NextHop" 2>/dev/null |
      tr -d '\r' | awk 'NF { print; exit }'
  fi
}

proxy_state() {
  [ -n "${CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE:-}" ] && { printf '%s\n' "$CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE"; return; }
  if [ -n "${http_proxy:-}${https_proxy:-}${all_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${ALL_PROXY:-}" ]; then
    printf env_proxy
    return
  fi

  os=$(detect_os)
  if [ "$os" = "macos" ] && command -v scutil >/dev/null 2>&1; then
    proxy_output=$(scutil --proxy 2>/dev/null) || { printf unknown; return; }
    if printf '%s\n' "$proxy_output" | awk '/ProxyAutoConfigEnable/ && $3 == "1" { found=1 } END { exit found ? 0 : 1 }'; then
      printf pac_proxy
      return
    fi
    if printf '%s\n' "$proxy_output" | awk '/HTTPEnable|HTTPSEnable|SOCKSEnable/ && $3 == "1" { found=1 } END { exit found ? 0 : 1 }'; then
      printf system_proxy
      return
    fi
    printf none
    return
  fi

  if [ "$os" = "linux" ] && command -v gsettings >/dev/null 2>&1; then
    desktop_proxy=$(gsettings get org.gnome.system.proxy mode 2>/dev/null) || { printf unknown; return; }
    case "$desktop_proxy" in
      *manual*) printf system_proxy; return ;;
      *auto*) printf pac_proxy; return ;;
      *none*) printf none; return ;;
    esac
  fi

  if command -v powershell.exe >/dev/null 2>&1; then
    win_proxy=$(powershell.exe -NoProfile -Command "try { \$s=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop; if ([int]\$s.ProxyEnable -eq 1) { 'system_proxy' } elseif ([string]\$s.AutoConfigURL) { 'pac_proxy' } else { 'none' } } catch { 'unknown' }" 2>/dev/null | tr -d '\r' | awk 'NF { print; exit }')
    printf '%s' "${win_proxy:-unknown}"
    return
  fi

  printf none
}

tun_state() {
  probe_address="$1"
  [ -n "${CLIENT_TOPOLOGY_FIXTURE_TUN_STATE:-}" ] && { printf '%s\n' "$CLIENT_TOPOLOGY_FIXTURE_TUN_STATE"; return; }
  [ -n "$probe_address" ] || { printf unknown; return; }

  default_device=""
  default_gateway_value=""
  effective_device=""
  effective_gateway=""
  if [ -n "${CLIENT_TOPOLOGY_FIXTURE_DEFAULT_ROUTE:-}" ] || [ -n "${CLIENT_TOPOLOGY_FIXTURE_EFFECTIVE_ROUTE:-}" ]; then
    [ -n "${CLIENT_TOPOLOGY_FIXTURE_DEFAULT_ROUTE:-}" ] || { printf unknown; return; }
    [ -n "${CLIENT_TOPOLOGY_FIXTURE_EFFECTIVE_ROUTE:-}" ] || { printf unknown; return; }
    default_gateway_value=$(printf '%s\n' "$CLIENT_TOPOLOGY_FIXTURE_DEFAULT_ROUTE" | awk -F'|' '{ print $1 }')
    default_device=$(printf '%s\n' "$CLIENT_TOPOLOGY_FIXTURE_DEFAULT_ROUTE" | awk -F'|' '{ print $2 }')
    effective_gateway=$(printf '%s\n' "$CLIENT_TOPOLOGY_FIXTURE_EFFECTIVE_ROUTE" | awk -F'|' '{ print $1 }')
    effective_device=$(printf '%s\n' "$CLIENT_TOPOLOGY_FIXTURE_EFFECTIVE_ROUTE" | awk -F'|' '{ print $2 }')
  elif command -v ip >/dev/null 2>&1; then
    default_line=$(ip route show default 2>/dev/null | awk 'NR == 1')
    effective_line=$(ip route get "$probe_address" 2>/dev/null | awk 'NR == 1')
    default_device=$(printf '%s\n' "$default_line" | awk '{ for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }')
    default_gateway_value=$(printf '%s\n' "$default_line" | awk '{ for (i=1; i<=NF; i++) if ($i == "via") { print $(i+1); exit } }')
    effective_device=$(printf '%s\n' "$effective_line" | awk '{ for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }')
    effective_gateway=$(printf '%s\n' "$effective_line" | awk '{ for (i=1; i<=NF; i++) if ($i == "via") { print $(i+1); exit } }')
  elif command -v route >/dev/null 2>&1 && [ "$(detect_os)" = "macos" ]; then
    default_output=$(route -n get default 2>/dev/null) || { printf unknown; return; }
    effective_output=$(route -n get "$probe_address" 2>/dev/null) || { printf unknown; return; }
    default_device=$(printf '%s\n' "$default_output" | awk '/interface:/ { print $2; exit }')
    default_gateway_value=$(printf '%s\n' "$default_output" | awk '/gateway:/ { print $2; exit }')
    effective_device=$(printf '%s\n' "$effective_output" | awk '/interface:/ { print $2; exit }')
    effective_gateway=$(printf '%s\n' "$effective_output" | awk '/gateway:/ { print $2; exit }')
  else
    printf unknown
    return
  fi

  [ -n "$effective_device" ] || { printf unknown; return; }
  [ -n "$default_device" ] || { printf unknown; return; }
  if [ "$effective_device" != "$default_device" ]; then
    printf present
  elif [ -n "$effective_gateway" ] && [ -n "$default_gateway_value" ] && [ "$effective_gateway" != "$default_gateway_value" ]; then
    printf present
  elif [ -z "$effective_gateway" ] && [ -n "$default_gateway_value" ]; then
    printf present
  else
    printf absent
  fi
}

dns_state() {
  [ -n "${CLIENT_TOPOLOGY_FIXTURE_DNS_STATE:-}" ] && { printf '%s\n' "$CLIENT_TOPOLOGY_FIXTURE_DNS_STATE"; return; }
  sample_host="${CLIENT_DNS_SAMPLE_HOST:-www.iana.org}"
  resolved=""
  if command -v getent >/dev/null 2>&1; then
    resolved=$(getent ahostsv4 "$sample_host" 2>/dev/null | awk '{ print $1; exit }')
  elif command -v nslookup >/dev/null 2>&1; then
    resolved=$(nslookup "$sample_host" 2>/dev/null | awk '/^Address: / { value=$2 } END { print value }')
  elif command -v powershell.exe >/dev/null 2>&1; then
    resolved=$(powershell.exe -NoProfile -Command "try { (Resolve-DnsName '$sample_host' -Type A -ErrorAction Stop | Select-Object -First 1 -ExpandProperty IPAddress) } catch { '' }" 2>/dev/null | tr -d '\r' | awk 'NF { print; exit }')
  fi

  case "$resolved" in
    28.*|198.18.*|198.19.*) printf "fake_ip:$resolved" ;;
    "") printf unknown ;;
    *) printf "ordinary:$resolved" ;;
  esac
}

http_probe() {
  [ -n "${CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE:-}" ] && { printf '%s\n' "$CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE"; return; }
  if command -v curl >/dev/null 2>&1; then
    code=$(curl -L -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$check_url" 2>/dev/null || true)
    case "$code" in
      2*|3*) printf "ok:$code" ;;
      *) printf "fail:${code:-000}" ;;
    esac
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    if wget -q -O /dev/null -T 10 "$check_url"; then
      printf ok
    else
      printf fail
    fi
    return
  fi
  if command -v powershell.exe >/dev/null 2>&1; then
    ps_code=$(CLIENT_CHECK_URL="$check_url" powershell.exe -NoProfile -Command 'try { $r = Invoke-WebRequest -Uri $env:CLIENT_CHECK_URL -UseBasicParsing -TimeoutSec 10; [int]$r.StatusCode } catch { "000" }' 2>/dev/null | tr -d '\r' | awk 'NF { print; exit }')
    case "$ps_code" in
      2*|3*) printf "ok:$ps_code" ;;
      *) printf "fail:${ps_code:-000}" ;;
    esac
    return
  fi
  printf skipped_missing_http_client
}

os_state=$(detect_os)
gateway=$(default_gateway)
expected_router=""
[ -n "$router" ] && expected_router=$(router_host "$router")
system_proxy_state=$(proxy_state)
client_dns_state=$(dns_state)
route_probe_address=""
case "$client_dns_state" in ordinary:*) route_probe_address=${client_dns_state#ordinary:} ;; esac
local_tun_state=$(tun_state "$route_probe_address")
client_http_state=$(http_probe)

client_runtime_present=0
case "$system_proxy_state" in none|unknown) ;; *) client_runtime_present=1 ;; esac
[ "$local_tun_state" = "present" ] && client_runtime_present=1
case "$client_dns_state" in fake_ip:*) client_runtime_present=1 ;; esac
if [ "$client_runtime_present" = "0" ] &&
  { [ "$system_proxy_state" = "unknown" ] || [ "$local_tun_state" = "unknown" ] || [ "$client_dns_state" = "unknown" ]; }; then
  client_runtime_present=unknown
fi

gateway_matches_router=unknown
if [ -n "$expected_router" ]; then
  if [ "$gateway" = "$expected_router" ]; then
    gateway_matches_router=yes
  else
    gateway_matches_router=no
  fi
fi

topology_mode=unknown
conflict_risk=unknown
if [ "$client_runtime_present" = "0" ] && [ "$gateway_matches_router" = "yes" ]; then
  topology_mode=router_primary
  conflict_risk=low
elif [ "$client_runtime_present" = "1" ] && [ "$gateway_matches_router" = "yes" ]; then
  topology_mode=hybrid
  conflict_risk=medium
elif [ "$client_runtime_present" = "1" ]; then
  topology_mode=client_fallback
  conflict_risk=low
elif [ "$client_runtime_present" = "0" ] && [ "$gateway_matches_router" = "no" ]; then
  topology_mode=not_using_router
  conflict_risk=medium
fi

echo "# Client Topology Check"
echo
print_kv "client_os" "$os_state"
print_kv "default_gateway" "$gateway"
print_kv "expected_router" "$expected_router"
print_kv "gateway_matches_router" "$gateway_matches_router"
print_kv "system_proxy_state" "$system_proxy_state"
print_kv "local_tun_state" "$local_tun_state"
print_kv "client_dns_state" "$client_dns_state"
print_kv "client_http_state" "$client_http_state"
print_kv "client_runtime_present" "$client_runtime_present"
print_kv "client_topology_mode" "$topology_mode"
print_kv "client_conflict_risk" "$conflict_risk"
