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
    [string]$Dns,
    [string]$RouterDns,
    [string]$ExpectedFakeIpOwner
  )

  $SavedEnvironment = @{}
  foreach ($FixtureName in @('OS', 'DEFAULT_GATEWAY', 'PROXY_STATE', 'TUN_STATE', 'DNS_STATE', 'ROUTER_DNS_STATE', 'HTTP_STATE')) {
    $Key = "CLIENT_TOPOLOGY_FIXTURE_$FixtureName"
    $SavedEnvironment[$Key] = [Environment]::GetEnvironmentVariable($Key)
  }
  $env:CLIENT_TOPOLOGY_FIXTURE_OS = "windows"
  $env:CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY = $Gateway
  $env:CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE = $Proxy
  $env:CLIENT_TOPOLOGY_FIXTURE_TUN_STATE = $Tun
  $env:CLIENT_TOPOLOGY_FIXTURE_DNS_STATE = $Dns
  $env:CLIENT_TOPOLOGY_FIXTURE_ROUTER_DNS_STATE = $RouterDns
  $env:CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE = "ok:204"

  try {
    $Output = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\check-client-topology.ps1") -Router "user@192.168.50.1" | Out-String
  }
  finally {
    foreach ($Key in $SavedEnvironment.Keys) {
      [Environment]::SetEnvironmentVariable($Key, $SavedEnvironment[$Key])
    }
  }

  $Mode = Get-StateValue $Output "client_topology_mode"
  $Runtime = Get-StateValue $Output "client_runtime_present"
  $Risk = Get-StateValue $Output "client_conflict_risk"
  $TunState = Get-StateValue $Output "local_tun_state"
  $FakeIpOwner = Get-StateValue $Output "fake_ip_owner"

  if ($Mode -ne $ExpectedMode) { throw "$Name expected mode=$ExpectedMode got=$Mode" }
  if ($Runtime -ne $ExpectedRuntime) { throw "$Name expected runtime=$ExpectedRuntime got=$Runtime" }
  if ($Risk -ne $ExpectedRisk) { throw "$Name expected risk=$ExpectedRisk got=$Risk" }
  if ($TunState -ne $Tun) { throw "$Name expected local_tun_state=$Tun got=$TunState" }
  if ($FakeIpOwner -ne $ExpectedFakeIpOwner) { throw "$Name expected fake_ip_owner=$ExpectedFakeIpOwner got=$FakeIpOwner" }
  if ($Gateway -eq 'unknown') {
    $GatewayMatch = Get-StateValue $Output 'gateway_matches_router'
    if ($GatewayMatch -ne 'unknown') { throw "$Name expected gateway_matches_router=unknown got=$GatewayMatch" }
  }
}

function Invoke-RouteCase {
  param(
    [string]$Name,
    [string]$RouteTable,
    [string]$ExpectedTun,
    [string]$ExpectedRuntime,
    [string]$ExpectedMode
  )

  $SavedEnvironment = @{}
  foreach ($FixtureName in @('OS', 'DEFAULT_GATEWAY', 'PROXY_STATE', 'TUN_STATE', 'DNS_STATE', 'ROUTER_DNS_STATE', 'HTTP_STATE', 'ROUTE_TABLE')) {
    $Key = "CLIENT_TOPOLOGY_FIXTURE_$FixtureName"
    $SavedEnvironment[$Key] = [Environment]::GetEnvironmentVariable($Key)
  }
  $env:CLIENT_TOPOLOGY_FIXTURE_OS = "windows"
  $env:CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY = "192.168.50.1"
  $env:CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE = "none"
  $env:CLIENT_TOPOLOGY_FIXTURE_DNS_STATE = "ordinary:142.250.0.1"
  $env:CLIENT_TOPOLOGY_FIXTURE_ROUTER_DNS_STATE = "ordinary:142.250.0.1"
  $env:CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE = "ok:204"
  $env:CLIENT_TOPOLOGY_FIXTURE_ROUTE_TABLE = $RouteTable
  $env:CLIENT_TOPOLOGY_FIXTURE_TUN_STATE = $null

  try {
    $Output = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\check-client-topology.ps1") -Router "user@192.168.50.1" | Out-String
  }
  finally {
    foreach ($Key in $SavedEnvironment.Keys) {
      [Environment]::SetEnvironmentVariable($Key, $SavedEnvironment[$Key])
    }
  }

  $TunState = Get-StateValue $Output "local_tun_state"
  $Runtime = Get-StateValue $Output "client_runtime_present"
  $Mode = Get-StateValue $Output "client_topology_mode"
  if ($TunState -ne $ExpectedTun) { throw "$Name expected local_tun_state=$ExpectedTun got=$TunState" }
  if ($Runtime -ne $ExpectedRuntime) { throw "$Name expected runtime=$ExpectedRuntime got=$Runtime" }
  if ($Mode -ne $ExpectedMode) { throw "$Name expected mode=$ExpectedMode got=$Mode" }
}

# Exercise the real route.exe parser when NetTCPIP cmdlets are unavailable.
# Dot-sourced functions and command mocks remain local to this test function.
function Test-OnLinkRouteFallback {
  $SavedEnvironment = @{}
  foreach ($FixtureName in @('TUN_STATE', 'ROUTE_TABLE', 'ROUTE_PRINT')) {
    $Key = "CLIENT_TOPOLOGY_FIXTURE_$FixtureName"
    $SavedEnvironment[$Key] = [Environment]::GetEnvironmentVariable($Key)
  }
  try {
    $env:CLIENT_TOPOLOGY_FIXTURE_TUN_STATE = $null
    $env:CLIENT_TOPOLOGY_FIXTURE_ROUTE_TABLE = $null
    $env:CLIENT_TOPOLOGY_FIXTURE_ROUTE_PRINT = @'
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0     192.168.50.1   192.168.50.10     25
          0.0.0.0        128.0.0.0         On-link        198.18.0.1      1
        128.0.0.0        128.0.0.0         On-link        198.18.0.1      1
'@
    function Get-NetRoute {
      [CmdletBinding()]
      param([string]$AddressFamily)
      throw 'fixture: Get-NetRoute unavailable'
    }
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'scripts/check-client-topology.ps1'), [ref]$Tokens, [ref]$Errors)
    if ($Errors.Count) { throw 'route fallback fixture source invalid' }
    foreach ($FunctionName in @('ConvertTo-PrefixLength', 'Get-WindowsRouteRows', 'ConvertTo-IPv4UInt32', 'Get-BestIPv4Route', 'Test-IPv4BenchmarkRange', 'Get-LocalTunState')) {
      $Function = $Ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $FunctionName }, $true)
      if (-not $Function) { throw "route fallback fixture missing $FunctionName" }
      . ([scriptblock]::Create($Function.Extent.Text))
    }
    $RoutePrint = $env:CLIENT_TOPOLOGY_FIXTURE_ROUTE_PRINT
    $LocalizedOnLink = [string]::Join('', [char[]]@(0x5728, 0x94FE, 0x8DEF, 0x4E0A))
    foreach ($GatewayToken in @('On-link', $LocalizedOnLink, 'Unrecognized-hop')) {
      $env:CLIENT_TOPOLOGY_FIXTURE_ROUTE_PRINT = $RoutePrint.Replace('On-link', $GatewayToken)
      $Expected = if ($GatewayToken -eq 'Unrecognized-hop') { 'unknown' } else { 'present' }
      foreach ($Address in @('8.8.8.8', '203.0.113.10')) {
        $Actual = Get-LocalTunState $Address
        if ($Actual -ne $Expected) { throw "on_link_route_fallback $Address expected $Expected got=$Actual" }
      }
    }
  }
  finally {
    foreach ($Key in $SavedEnvironment.Keys) {
      [Environment]::SetEnvironmentVariable($Key, $SavedEnvironment[$Key])
    }
  }
}
Test-OnLinkRouteFallback

Invoke-Case router_primary router_primary 0 low 192.168.50.1 none absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
Invoke-Case hybrid hybrid 1 medium 192.168.50.1 none present fake_ip:198.18.0.2 fake_ip:198.18.0.2 router
Invoke-Case client_fallback client_fallback 1 low 192.168.99.1 env_proxy absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
Invoke-Case persistent_user_proxy hybrid 1 medium 192.168.50.1 user_env_proxy absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
Invoke-Case not_using_router not_using_router 0 medium 192.168.99.1 none absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
Invoke-Case pac_proxy hybrid 1 medium 192.168.50.1 pac_proxy absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
Invoke-Case fake_ip_without_visible_route hybrid 1 medium 192.168.50.1 none unknown fake_ip:198.18.0.2 ordinary:142.250.0.1 client
Invoke-Case router_fake_ip_without_client_runtime router_primary 0 low 192.168.50.1 none absent fake_ip:28.0.0.42 fake_ip:28.0.0.42 router
Invoke-Case unattributed_fake_ip unknown unknown unknown 192.168.50.1 none absent fake_ip:28.0.0.42 unknown unknown
Invoke-Case unnamed_path_interceptor hybrid 1 medium 192.168.50.1 none present ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
Invoke-Case inspection_unknown unknown unknown unknown 192.168.50.1 unknown unknown unknown unknown not_applicable
Invoke-Case overlay_not_on_path router_primary 0 low 192.168.50.1 none absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
Invoke-Case unknown_gateway_without_proxy unknown 0 unknown unknown none absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
Invoke-Case unknown_gateway_with_proxy unknown 1 unknown unknown env_proxy absent ordinary:142.250.0.1 ordinary:142.250.0.1 not_applicable
Invoke-RouteCase route_owned_by_unnamed_interceptor "0.0.0.0/0|192.168.50.1|10|25|25;142.250.0.0/16|0.0.0.0|20|1|1" present 1 hybrid
Invoke-RouteCase benchmark_default_interceptor "0.0.0.0/0|198.18.0.2|48|0|0" present 1 hybrid
Invoke-RouteCase unrelated_overlay_route "0.0.0.0/0|192.168.50.1|10|25|25;100.64.0.0/10|0.0.0.0|20|1|1" absent 0 router_primary
Invoke-RouteCase combined_metric_specific_route "0.0.0.0/0|192.168.50.1|10|25|25;142.250.0.0/16|0.0.0.0|20|1|100;142.250.0.0/16|192.168.50.1|10|20|5" absent 0 router_primary
Invoke-RouteCase combined_metric_default_route "0.0.0.0/0|198.18.0.2|20|1|100;0.0.0.0/0|192.168.50.1|10|20|5;142.250.0.0/16|192.168.50.1|10|20|5" absent 0 router_primary
Invoke-RouteCase longest_prefix_before_metric "0.0.0.0/0|192.168.50.1|10|1|1;142.250.0.0/16|0.0.0.0|20|100|100" present 1 hybrid


# Exercise the real Windows gateway selectors without reading host networking.
function Test-CombinedGatewayMetric {
  $SavedGateway = $env:CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY
  try {
    $env:CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY = $null
    function Get-NetRoute {
      [CmdletBinding()]
      param([string]$DestinationPrefix)
      [pscustomobject]@{ NextHop = '198.18.0.2'; RouteMetric = 1; InterfaceMetric = 100 }
      [pscustomobject]@{ NextHop = '192.168.50.1'; RouteMetric = 20; InterfaceMetric = 5 }
    }
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'scripts/check-client-topology.ps1'), [ref]$Tokens, [ref]$Errors)
    $Function = $Ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Get-DefaultGateway' }, $true)
    if (-not $Function -or $Errors.Count) { throw 'gateway fixture source invalid' }
    . ([scriptblock]::Create($Function.Extent.Text))
    if ((Get-DefaultGateway) -ne '192.168.50.1') { throw 'PowerShell gateway ignored combined metric' }
    $Shell = [IO.File]::ReadAllText((Join-Path $Repo 'scripts/check-client-topology.sh'))
    $Command = [regex]::Match($Shell, "(?m)powershell.exe -NoProfile -Command '([^'\r\n]*Get-NetRoute[^'\r\n]*)'")
    if (-not $Command.Success) { throw 'Windows shell gateway fixture source missing' }
    if ((& ([scriptblock]::Create($Command.Groups[1].Value))) -ne '192.168.50.1') { throw 'Windows shell gateway ignored combined metric' }
  }
  finally { $env:CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY = $SavedGateway }
}
Test-CombinedGatewayMetric

$ProductCatalogPattern = "(?i)flclash|tailscale|zerotier|hiddify"
foreach ($Detector in @("scripts\check-client-topology.ps1", "scripts\check-client-topology.sh")) {
  $Source = Get-Content -LiteralPath (Join-Path $Repo $Detector) -Raw
  if ($Source -match $ProductCatalogPattern) {
    throw "$Detector still classifies client topology through product names"
  }
  if ($Source -notmatch [regex]::Escape("HKCU:\Environment")) {
    throw "$Detector does not inspect persistent Windows proxy environment"
  }
}

Write-Host "client_topology_fixture_tests=ok"
