param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$FixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("home-edge-closeout-client-fixture-" + [System.Guid]::NewGuid().ToString("N"))
$FixtureScripts = Join-Path $FixtureRoot "scripts"
New-Item -ItemType Directory -Force -Path $FixtureScripts | Out-Null

function Write-FixtureScript {
  param([string]$Name, [string]$Content)
  Set-Content -LiteralPath (Join-Path $FixtureScripts $Name) -Value $Content -Encoding UTF8
}

function Get-StateValue {
  param([string]$Text, [string]$Key)
  $Match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Key))=(.+)$")
  if ($Match.Success) { return $Match.Groups[1].Value.Trim() }
  return ""
}

function Invoke-Case {
  param(
    [string]$Name,
    [string]$Runtime,
    [string]$ExpectedGate,
    [string]$ExpectedCloseout,
    [string]$Consumption = "runtime_profile_matches_cache",
    [string]$ExpectedSubscriptionGate = "pass",
    [string]$DashboardConfig = "not_configured",
    [string]$DashboardReachability = "unverified",
    [switch]$DashboardConfirmed,
    [switch]$AcceptRuntimeImportedSubscription,
    [string]$ExpectedDashboardGate = "not_applicable",
    [string]$ExpectedDashboardEvidence = "not_applicable"
  )

  $env:INSTALLATION_CLOSEOUT_CLIENT_RUNTIME = $Runtime
  $env:INSTALLATION_CLOSEOUT_SUB_CONSUMPTION = $Consumption
  $env:INSTALLATION_CLOSEOUT_DASHBOARD_CONFIG = $DashboardConfig
  $env:INSTALLATION_CLOSEOUT_DASHBOARD_REACHABILITY = $DashboardReachability
  try {
    $Args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $Repo "scripts\check-installation-closeout.ps1"), "-Router", "user@192.168.50.1", "-RunClientCheck", "-Repo", $FixtureRoot)
    if ($DashboardConfirmed) { $Args += "-DashboardConfirmed" }
    if ($AcceptRuntimeImportedSubscription) { $Args += "-AcceptRuntimeImportedSubscription" }
    $Output = powershell @Args | Out-String
  }
  finally {
    Remove-Item Env:\INSTALLATION_CLOSEOUT_CLIENT_RUNTIME -ErrorAction SilentlyContinue
    Remove-Item Env:\INSTALLATION_CLOSEOUT_SUB_CONSUMPTION -ErrorAction SilentlyContinue
    Remove-Item Env:\INSTALLATION_CLOSEOUT_DASHBOARD_CONFIG -ErrorAction SilentlyContinue
    Remove-Item Env:\INSTALLATION_CLOSEOUT_DASHBOARD_REACHABILITY -ErrorAction SilentlyContinue
  }

  $Gate = Get-StateValue $Output "client_gate"
  $Closeout = Get-StateValue $Output "installation_closeout_state"
  $SubscriptionGate = Get-StateValue $Output "subscription_gate"
  $DashboardGate = Get-StateValue $Output "dashboard_gate"
  $DashboardEvidence = Get-StateValue $Output "dashboard_evidence"
  $NextAction = Get-StateValue $Output "next_action"
  if ($Gate -ne $ExpectedGate) { throw "$Name expected client_gate=$ExpectedGate got=$Gate" }
  if ($SubscriptionGate -ne $ExpectedSubscriptionGate) { throw "$Name expected subscription_gate=$ExpectedSubscriptionGate got=$SubscriptionGate" }
  if ($DashboardGate -ne $ExpectedDashboardGate) { throw "$Name expected dashboard_gate=$ExpectedDashboardGate got=$DashboardGate" }
  if ($DashboardEvidence -ne $ExpectedDashboardEvidence) { throw "$Name expected dashboard_evidence=$ExpectedDashboardEvidence got=$DashboardEvidence" }
  if ($Closeout -ne $ExpectedCloseout) { throw "$Name expected installation_closeout_state=$ExpectedCloseout got=$Closeout" }
  if ($Runtime -eq "unknown" -and $NextAction -notmatch "read-only client topology check") {
    throw "$Name expected an actionable read-only topology recheck, got=$NextAction"
  }
}

try {
  Write-FixtureScript "verify-closeout.ps1" @'
param([string]$Repo)
Write-Host "closeout_state=ready"
'@
  Write-FixtureScript "guide-router.ps1" @'
param([string]$Router, [switch]$NoPause)
@"
device_state=ssh_reachable
admin_state=jffs_scripts_ready
baseline_state=reviewed
proxy_state=verified
runtime_state=running
runtime_process_state=$($env:INSTALLATION_CLOSEOUT_RUNTIME_PROCESS)
controller_state=reachable
controller_auth_state=authenticated
controller_observation_state=ready
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
subscription_consumption_state=$($env:INSTALLATION_CLOSEOUT_SUB_CONSUMPTION)
dashboard_config_state=$($env:INSTALLATION_CLOSEOUT_DASHBOARD_CONFIG)
dashboard_reachability_state=$($env:INSTALLATION_CLOSEOUT_DASHBOARD_REACHABILITY)
automation_state=live_managed
risk_count=0
review_count=0
monitor_count=0
"@ | Write-Host
'@
  Write-FixtureScript "check-router-status.ps1" @'
param([string]$Router, [switch]$NoPause)
Write-Host "controller_observation_state=ready"
Write-Host "self-heal: OK current=Fixture Route reaches probe target; no change"
Write-Host "route_evidence_probe_id=$($env:INSTALLATION_CLOSEOUT_ROUTE_PROBE_ID)"
Write-Host "route_evidence_identity=Fixture Route"
Write-Host "route_evidence_classification=reachable"
Write-Host "route_evidence_verification_state=$($env:INSTALLATION_CLOSEOUT_ROUTE_STATE)"
'@
  Write-FixtureScript "check-client-topology.ps1" @'
param([string]$Router, [string]$ClientCheckUrl)
$Runtime = $env:INSTALLATION_CLOSEOUT_CLIENT_RUNTIME
$Mode = if ($Runtime -eq "0") { "router_primary" } elseif ($Runtime -eq "1") { "hybrid" } else { "unknown" }
$Risk = if ($Runtime -eq "0") { "low" } elseif ($Runtime -eq "1") { "medium" } else { "unknown" }
Write-Host "client_topology_mode=$Mode"
Write-Host "client_runtime_present=$Runtime"
Write-Host "gateway_matches_router=yes"
Write-Host "client_http_state=ok:204"
Write-Host "client_conflict_risk=$Risk"
'@

  $env:INSTALLATION_CLOSEOUT_RUNTIME_PROCESS = "running"
  $env:INSTALLATION_CLOSEOUT_ROUTE_PROBE_ID = "fixture-1"
  $env:INSTALLATION_CLOSEOUT_ROUTE_STATE = "pass"

  Invoke-Case router_primary 0 pass pass
  Invoke-Case known_runtime 1 client_runtime_present partial
  Invoke-Case unknown_runtime unknown client_runtime_unknown partial
  Invoke-Case cache_not_consumed 0 pass partial cache_only_unverified consumption_unverified
  Invoke-Case accepted_subscription_boundary 0 pass accepted_boundary cache_only_unverified accepted_manual_boundary not_configured unverified -AcceptRuntimeImportedSubscription
  Invoke-Case configured_dashboard_unverified 0 pass partial runtime_profile_matches_cache pass configured unverified -ExpectedDashboardGate reachability_unverified -ExpectedDashboardEvidence unverified
  Invoke-Case confirmed_dashboard 0 pass pass runtime_profile_matches_cache pass configured unverified -DashboardConfirmed -ExpectedDashboardGate pass -ExpectedDashboardEvidence user_confirmed

  $env:INSTALLATION_CLOSEOUT_ROUTE_PROBE_ID = ""
  $env:INSTALLATION_CLOSEOUT_ROUTE_STATE = "fail"
  Invoke-Case stale_route_log 0 pass fail
  $env:INSTALLATION_CLOSEOUT_ROUTE_PROBE_ID = "fixture-2"
  $env:INSTALLATION_CLOSEOUT_ROUTE_STATE = "pass"
  $env:INSTALLATION_CLOSEOUT_RUNTIME_PROCESS = "unknown"
  Invoke-Case unknown_runtime_process 0 pass fail
  $env:INSTALLATION_CLOSEOUT_RUNTIME_PROCESS = "not_detected"
  Invoke-Case absent_runtime_process 0 pass fail
}
finally {
  Remove-Item Env:\INSTALLATION_CLOSEOUT_RUNTIME_PROCESS -ErrorAction SilentlyContinue
  Remove-Item Env:\INSTALLATION_CLOSEOUT_ROUTE_PROBE_ID -ErrorAction SilentlyContinue
  Remove-Item Env:\INSTALLATION_CLOSEOUT_ROUTE_STATE -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $FixtureRoot -PathType Container) {
    Remove-Item -LiteralPath $FixtureRoot -Recurse -Force
  }
}

Write-Host "installation_closeout_client_fixture_tests=ok"
