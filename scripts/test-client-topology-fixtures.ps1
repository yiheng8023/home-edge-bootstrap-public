param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

function Get-StateValue {
  param(
    [string]$Text,
    [string]$Key
  )
  $Match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Key))=(.+)$")
  if ($Match.Success) { return $Match.Groups[1].Value.Trim() }
  return ""
}

function Invoke-Case {
  param(
    [string]$Name,
    [string]$ExpectedMode,
    [string]$ExpectedRuntime,
    [string]$ExpectedRisk,
    [string]$Gateway,
    [string]$Proxy,
    [string]$Tun,
    [string]$Dns
  )

  $env:CLIENT_TOPOLOGY_FIXTURE_OS = "windows"
  $env:CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY = $Gateway
  $env:CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE = $Proxy
  $env:CLIENT_TOPOLOGY_FIXTURE_TUN_STATE = $Tun
  $env:CLIENT_TOPOLOGY_FIXTURE_DNS_STATE = $Dns
  $env:CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE = "ok:204"

  try {
    $Output = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\check-client-topology.ps1") -Router "user@192.168.50.1" | Out-String
  }
  finally {
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_OS -ErrorAction SilentlyContinue
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY -ErrorAction SilentlyContinue
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_TUN_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_DNS_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE -ErrorAction SilentlyContinue
  }

  $Mode = Get-StateValue $Output "client_topology_mode"
  $Runtime = Get-StateValue $Output "client_runtime_present"
  $Risk = Get-StateValue $Output "client_conflict_risk"
  $TunState = Get-StateValue $Output "local_tun_state"

  if ($Mode -ne $ExpectedMode) { throw "$Name expected mode=$ExpectedMode got=$Mode" }
  if ($Runtime -ne $ExpectedRuntime) { throw "$Name expected runtime=$ExpectedRuntime got=$Runtime" }
  if ($Risk -ne $ExpectedRisk) { throw "$Name expected risk=$ExpectedRisk got=$Risk" }
  if ($TunState -ne $Tun) { throw "$Name expected local_tun_state=$Tun got=$TunState" }
}

function Invoke-RouteCase {
  param(
    [string]$Name,
    [string]$RouteTable,
    [string]$ExpectedTun,
    [string]$ExpectedRuntime,
    [string]$ExpectedMode
  )

  $env:CLIENT_TOPOLOGY_FIXTURE_OS = "windows"
  $env:CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY = "192.168.50.1"
  $env:CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE = "none"
  $env:CLIENT_TOPOLOGY_FIXTURE_DNS_STATE = "ordinary:142.250.0.1"
  $env:CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE = "ok:204"
  $env:CLIENT_TOPOLOGY_FIXTURE_ROUTE_TABLE = $RouteTable

  try {
    $Output = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\check-client-topology.ps1") -Router "user@192.168.50.1" | Out-String
  }
  finally {
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_OS -ErrorAction SilentlyContinue
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY -ErrorAction SilentlyContinue
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_DNS_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_ROUTE_TABLE -ErrorAction SilentlyContinue
  }

  $TunState = Get-StateValue $Output "local_tun_state"
  $Runtime = Get-StateValue $Output "client_runtime_present"
  $Mode = Get-StateValue $Output "client_topology_mode"
  if ($TunState -ne $ExpectedTun) { throw "$Name expected local_tun_state=$ExpectedTun got=$TunState" }
  if ($Runtime -ne $ExpectedRuntime) { throw "$Name expected runtime=$ExpectedRuntime got=$Runtime" }
  if ($Mode -ne $ExpectedMode) { throw "$Name expected mode=$ExpectedMode got=$Mode" }
}

Invoke-Case router_primary router_primary 0 low 192.168.50.1 none absent ordinary:142.250.0.1
Invoke-Case hybrid hybrid 1 medium 192.168.50.1 none present fake_ip:198.18.0.2
Invoke-Case client_fallback client_fallback 1 low 192.168.99.1 env_proxy absent ordinary:142.250.0.1
Invoke-Case not_using_router not_using_router 0 medium 192.168.99.1 none absent ordinary:142.250.0.1
Invoke-Case pac_proxy hybrid 1 medium 192.168.50.1 pac_proxy absent ordinary:142.250.0.1
Invoke-Case fake_ip_without_visible_route hybrid 1 medium 192.168.50.1 none unknown fake_ip:198.18.0.2
Invoke-Case unnamed_path_interceptor hybrid 1 medium 192.168.50.1 none present ordinary:142.250.0.1
Invoke-Case inspection_unknown unknown unknown unknown 192.168.50.1 unknown unknown unknown
Invoke-Case overlay_not_on_path router_primary 0 low 192.168.50.1 none absent ordinary:142.250.0.1
Invoke-RouteCase route_owned_by_unnamed_interceptor "0.0.0.0/0|192.168.50.1|10|25|25;142.250.0.0/16|0.0.0.0|20|1|1" present 1 hybrid
Invoke-RouteCase unrelated_overlay_route "0.0.0.0/0|192.168.50.1|10|25|25;100.64.0.0/10|0.0.0.0|20|1|1" absent 0 router_primary

$ProductCatalogPattern = "(?i)flclash|tailscale|zerotier|hiddify"
foreach ($Detector in @("scripts\check-client-topology.ps1", "scripts\check-client-topology.sh")) {
  $Source = Get-Content -LiteralPath (Join-Path $Repo $Detector) -Raw
  if ($Source -match $ProductCatalogPattern) {
    throw "$Detector still classifies client topology through product names"
  }
}

Write-Host "client_topology_fixture_tests=ok"
