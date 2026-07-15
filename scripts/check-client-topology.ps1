param(
  [string]$Router = $env:ROUTER,
  [string]$ClientCheckUrl = $(if ($env:CLIENT_CHECK_URL) { $env:CLIENT_CHECK_URL } else { "https://cp.cloudflare.com/generate_204" }),
  [string]$DnsSampleHost = $(if ($env:CLIENT_DNS_SAMPLE_HOST) { $env:CLIENT_DNS_SAMPLE_HOST } else { "www.iana.org" })
)

$ErrorActionPreference = "Stop"

function Write-Kv {
  param([string]$Key, [string]$Value)
  if (-not $Value) { $Value = "unknown" }
  Write-Host "$Key=$Value"
}

function Get-RouterHost {
  param([string]$Value)
  if (-not $Value) { return "" }
  if ($Value -match "@([^@]+)$") { return $Matches[1] }
  return $Value
}

function Get-DefaultGateway {
  if ($env:CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY) { return $env:CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY }
  try {
    $Route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
      Sort-Object RouteMetric, InterfaceMetric |
      Select-Object -First 1
    if ($Route) { return [string]$Route.NextHop }
  }
  catch {
    return ""
  }
  return ""
}

function Get-SystemProxyState {
  if ($env:CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE) { return $env:CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE }
  $EnvProxy = @(
    $env:http_proxy, $env:https_proxy, $env:all_proxy,
    $env:HTTP_PROXY, $env:HTTPS_PROXY, $env:ALL_PROXY
  ) | Where-Object { $_ }
  if ($EnvProxy.Count -gt 0) { return "env_proxy" }

  try {
    $Settings = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction Stop
    if ([int]$Settings.ProxyEnable -eq 1) { return "system_proxy" }
    if ([string]$Settings.AutoConfigURL) { return "pac_proxy" }
  }
  catch {
    return "unknown"
  }

  return "none"
}

function ConvertTo-IPv4UInt32 {
  param([string]$Address)
  $Bytes = [System.Net.IPAddress]::Parse($Address).GetAddressBytes()
  if ($Bytes.Count -ne 4) { throw "IPv4 address required" }
  return [uint32]((([uint64]$Bytes[0]) -shl 24) -bor
    (([uint64]$Bytes[1]) -shl 16) -bor
    (([uint64]$Bytes[2]) -shl 8) -bor
    ([uint64]$Bytes[3]))
}

function Get-BestIPv4Route {
  param(
    [string]$Address,
    [object[]]$Routes
  )

  $AddressValue = ConvertTo-IPv4UInt32 $Address
  $Candidates = foreach ($Route in $Routes) {
    $Parts = ([string]$Route.DestinationPrefix) -split "/", 2
    if ($Parts.Count -ne 2) { continue }
    $PrefixLength = 0
    if (-not [int]::TryParse($Parts[1], [ref]$PrefixLength) -or $PrefixLength -lt 0 -or $PrefixLength -gt 32) {
      continue
    }
    try {
      $NetworkValue = ConvertTo-IPv4UInt32 $Parts[0]
    }
    catch {
      continue
    }
    $Mask = if ($PrefixLength -eq 0) {
      [uint32]0
    }
    else {
      [uint32](([uint64]4294967295 -shl (32 - $PrefixLength)) -band [uint64]4294967295)
    }
    if (($AddressValue -band $Mask) -eq ($NetworkValue -band $Mask)) {
      [pscustomobject]@{
        PrefixLength = $PrefixLength
        Route = $Route
      }
    }
  }

  $Selected = $Candidates |
    Sort-Object @{ Expression = "PrefixLength"; Descending = $true },
      @{ Expression = { [int]$_.Route.RouteMetric }; Descending = $false },
      @{ Expression = { [int]$_.Route.InterfaceMetric }; Descending = $false } |
    Select-Object -First 1
  if ($Selected) { return $Selected.Route }
  return $null
}

function Get-LocalTunState {
  param([string]$ProbeAddress)
  if ($env:CLIENT_TOPOLOGY_FIXTURE_TUN_STATE) { return $env:CLIENT_TOPOLOGY_FIXTURE_TUN_STATE }
  if (-not $ProbeAddress -or $ProbeAddress -notmatch "^\d+\.\d+\.\d+\.\d+$") { return "unknown" }
  try {
    if ($env:CLIENT_TOPOLOGY_FIXTURE_ROUTE_TABLE) {
      $Routes = @(
        foreach ($Entry in ($env:CLIENT_TOPOLOGY_FIXTURE_ROUTE_TABLE -split ";")) {
          $Fields = $Entry -split "\|", 5
          if ($Fields.Count -ne 5) { throw "invalid route-table fixture entry" }
          [pscustomobject]@{
            DestinationPrefix = $Fields[0]
            NextHop = $Fields[1]
            InterfaceIndex = [int]$Fields[2]
            RouteMetric = [int]$Fields[3]
            InterfaceMetric = [int]$Fields[4]
          }
        }
      )
    }
    else {
      $Routes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop)
    }
    $DefaultRoute = $Routes |
      Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } |
      Sort-Object RouteMetric, InterfaceMetric |
      Select-Object -First 1
    $EffectiveRoute = Get-BestIPv4Route -Address $ProbeAddress -Routes $Routes
    if (-not $DefaultRoute -or -not $EffectiveRoute) { return "unknown" }
    if ([int]$EffectiveRoute.InterfaceIndex -ne [int]$DefaultRoute.InterfaceIndex) { return "present" }

    $EffectiveNextHop = [string]$EffectiveRoute.NextHop
    $DefaultNextHop = [string]$DefaultRoute.NextHop
    if ($EffectiveNextHop -and $DefaultNextHop -and
      $EffectiveNextHop -ne "0.0.0.0" -and
      $EffectiveNextHop -ne $DefaultNextHop) {
      return "present"
    }
    if ($EffectiveRoute.DestinationPrefix -ne "0.0.0.0/0" -and
      $EffectiveNextHop -eq "0.0.0.0" -and
      $DefaultNextHop -and $DefaultNextHop -ne "0.0.0.0") {
      return "present"
    }
    return "absent"
  }
  catch {
    return "unknown"
  }
}

function Get-DnsState {
  param([string]$HostName)
  if ($env:CLIENT_TOPOLOGY_FIXTURE_DNS_STATE) { return $env:CLIENT_TOPOLOGY_FIXTURE_DNS_STATE }
  try {
    $Address = Resolve-DnsName $HostName -Type A -ErrorAction Stop |
      Select-Object -First 1 -ExpandProperty IPAddress
    if (-not $Address) { return "unknown" }
    if ($Address -match "^(28\.|198\.18\.|198\.19\.)") { return "fake_ip:$Address" }
    return "ordinary:$Address"
  }
  catch {
    return "unknown"
  }
}

function Invoke-HttpProbe {
  param([string]$Url)
  if ($env:CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE) { return $env:CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE }
  try {
    $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
    $Code = [int]$Response.StatusCode
    if ($Code -ge 200 -and $Code -lt 400) { return "ok:$Code" }
    return "fail:$Code"
  }
  catch {
    return "fail:000"
  }
}

$ExpectedRouter = Get-RouterHost $Router
$DefaultGateway = Get-DefaultGateway
$SystemProxyState = Get-SystemProxyState
$ClientDnsState = Get-DnsState $DnsSampleHost
$RouteProbeAddress = ""
if ($ClientDnsState -match "^ordinary:(\d+\.\d+\.\d+\.\d+)$") {
  $RouteProbeAddress = $Matches[1]
}
$LocalTunState = Get-LocalTunState $RouteProbeAddress
$ClientHttpState = Invoke-HttpProbe $ClientCheckUrl

$ClientRuntimePresent = "0"
if ($SystemProxyState -notin @("none", "unknown") -or
  $LocalTunState -eq "present" -or
  $ClientDnsState -like "fake_ip:*") {
  $ClientRuntimePresent = "1"
}
elseif ($SystemProxyState -eq "unknown" -or
  $LocalTunState -eq "unknown" -or
  $ClientDnsState -eq "unknown") {
  $ClientRuntimePresent = "unknown"
}

$GatewayMatchesRouter = "unknown"
if ($ExpectedRouter) {
  if ($DefaultGateway -eq $ExpectedRouter) {
    $GatewayMatchesRouter = "yes"
  }
  else {
    $GatewayMatchesRouter = "no"
  }
}

$TopologyMode = "unknown"
$ConflictRisk = "unknown"
if ($ClientRuntimePresent -eq "0" -and $GatewayMatchesRouter -eq "yes") {
  $TopologyMode = "router_primary"
  $ConflictRisk = "low"
}
elseif ($ClientRuntimePresent -eq "1" -and $GatewayMatchesRouter -eq "yes") {
  $TopologyMode = "hybrid"
  $ConflictRisk = "medium"
}
elseif ($ClientRuntimePresent -eq "1") {
  $TopologyMode = "client_fallback"
  $ConflictRisk = "low"
}
elseif ($ClientRuntimePresent -eq "0" -and $GatewayMatchesRouter -eq "no") {
  $TopologyMode = "not_using_router"
  $ConflictRisk = "medium"
}

Write-Host "# Client Topology Check"
Write-Host ""
Write-Kv "client_os" $(if ($env:CLIENT_TOPOLOGY_FIXTURE_OS) { $env:CLIENT_TOPOLOGY_FIXTURE_OS } else { "windows" })
Write-Kv "default_gateway" $DefaultGateway
Write-Kv "expected_router" $ExpectedRouter
Write-Kv "gateway_matches_router" $GatewayMatchesRouter
Write-Kv "system_proxy_state" $SystemProxyState
Write-Kv "local_tun_state" $LocalTunState
Write-Kv "client_dns_state" $ClientDnsState
Write-Kv "client_http_state" $ClientHttpState
Write-Kv "client_runtime_present" ([string]$ClientRuntimePresent)
Write-Kv "client_topology_mode" $TopologyMode
Write-Kv "client_conflict_risk" $ConflictRisk
