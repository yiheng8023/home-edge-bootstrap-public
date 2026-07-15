param(
  [Parameter(Mandatory = $true)]
  [string]$Router,
  [string]$AuditLogPath = "C:\tmp\home-edge-health-audit.log",
  [string]$KnownHostsFile = "C:\tmp\home-edge-bootstrap-known-hosts",
  [switch]$Json
)

$ErrorActionPreference = "Continue"

function Get-StateValue {
  param(
    [string]$Text,
    [string]$Key
  )
  $Match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Key))=(.+)$")
  if ($Match.Success) { return $Match.Groups[1].Value.Trim() }
  return ""
}

function Or-Unknown {
  param([string]$Value)
  if ($Value) { return $Value }
  return "unknown"
}

function Run-Capture {
  param([scriptblock]$Block)
  $Output = & $Block 2>&1 | Out-String
  return $Output
}

$GuideScript = Join-Path $PSScriptRoot "guide-router.ps1"
$ClientScript = Join-Path $PSScriptRoot "check-client-topology.ps1"

if ($env:EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT) {
  $GuideOutput = $env:EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT
  $GuideExit = 0
  if ($env:EDGE_HEALTH_FIXTURE_GUIDE_EXIT) { $GuideExit = [int]$env:EDGE_HEALTH_FIXTURE_GUIDE_EXIT }
}
else {
  $GuideOutput = Run-Capture { powershell -NoProfile -ExecutionPolicy Bypass -File $GuideScript -Router $Router -AuditLogPath $AuditLogPath -KnownHostsFile $KnownHostsFile -NoPause }
  $GuideExit = $LASTEXITCODE
}

if ($env:EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT) {
  $ClientOutput = $env:EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT
  $ClientExit = 0
  if ($env:EDGE_HEALTH_FIXTURE_CLIENT_EXIT) { $ClientExit = [int]$env:EDGE_HEALTH_FIXTURE_CLIENT_EXIT }
}
else {
  $ClientOutput = Run-Capture { powershell -NoProfile -ExecutionPolicy Bypass -File $ClientScript -Router $Router }
  $ClientExit = $LASTEXITCODE
}

$DeviceState = Get-StateValue $GuideOutput "device_state"
$BaselineState = Get-StateValue $GuideOutput "baseline_state"
$ProxyState = Get-StateValue $GuideOutput "proxy_state"
$RuntimeState = Get-StateValue $GuideOutput "runtime_state"
$ControllerState = Get-StateValue $GuideOutput "controller_state"
$ControllerAuthState = Get-StateValue $GuideOutput "controller_auth_state"
$SelfHealRegistrationState = Get-StateValue $GuideOutput "self_heal_registration_state"
$SelfHealBootHookState = Get-StateValue $GuideOutput "self_heal_boot_hook_state"
$SubscriptionState = Get-StateValue $GuideOutput "subscription_state"
$SubscriptionConsumptionState = Get-StateValue $GuideOutput "subscription_consumption_state"
$AutomationState = Get-StateValue $GuideOutput "automation_state"
$RiskCount = Get-StateValue $GuideOutput "risk_count"
$ReviewCount = Get-StateValue $GuideOutput "review_count"
$MonitorCount = Get-StateValue $GuideOutput "monitor_count"

$ClientTopologyMode = Get-StateValue $ClientOutput "client_topology_mode"
$ClientRuntimePresent = Get-StateValue $ClientOutput "client_runtime_present"
$ClientConflictRisk = Get-StateValue $ClientOutput "client_conflict_risk"
$GatewayMatchesRouter = Get-StateValue $ClientOutput "gateway_matches_router"
$ClientHttpState = Get-StateValue $ClientOutput "client_http_state"

$HealthState = "partial"
$NextAction = "inspect guide-router output"
if ($GuideExit -ne 0) {
  $HealthState = "router_audit_failed"
  $NextAction = "fix SSH/router reachability, then rerun guide-router"
}
elseif ($ProxyState -ne "absent" -and ($SelfHealRegistrationState -ne "ready" -or $SelfHealBootHookState -ne "ready")) {
  $HealthState = "lifecycle_registration_degraded"
  $NextAction = "repair project-owned boot and scheduler registration"
}
elseif ($RuntimeState -eq "authentication_blocked") {
  $HealthState = "controller_auth_blocked"
  $NextAction = "configure matching controller secret in router-local policy"
}
elseif ($RuntimeState -eq "controller_unreachable") {
  $HealthState = "runtime_unreachable"
  $NextAction = "inspect or start proxy runtime through its adapter or native interface"
}
elseif ($ProxyState -eq "verified" -and $AutomationState -eq "live_managed") {
  $HealthState = "router_managed"
  $NextAction = "none"
}
elseif ($ProxyState -eq "verified") {
  $HealthState = "router_usable"
  $NextAction = "enable live self-heal after dry-run review"
}
elseif ($ProxyState -eq "api_reachable") {
  $HealthState = "runtime_needs_route_verification"
  $NextAction = "inspect self-heal dry-run and route status"
}
elseif ($SubscriptionState -eq "missing") {
  $HealthState = "subscription_missing"
  $NextAction = "store provider subscription or import through ShellCrash"
}

if ($ClientExit -ne 0) {
  $ClientTopologyMode = "unknown"
  $ClientRuntimePresent = "unknown"
  $ClientConflictRisk = "unknown"
  $GatewayMatchesRouter = "unknown"
  $ClientHttpState = "unknown"
}

$Summary = [ordered]@{
  edge_health_state = $HealthState
  device_state = (Or-Unknown $DeviceState)
  baseline_state = (Or-Unknown $BaselineState)
  proxy_state = (Or-Unknown $ProxyState)
  runtime_state = (Or-Unknown $RuntimeState)
  controller_state = (Or-Unknown $ControllerState)
  controller_auth_state = (Or-Unknown $ControllerAuthState)
  self_heal_registration_state = (Or-Unknown $SelfHealRegistrationState)
  self_heal_boot_hook_state = (Or-Unknown $SelfHealBootHookState)
  subscription_state = (Or-Unknown $SubscriptionState)
  subscription_consumption_state = (Or-Unknown $SubscriptionConsumptionState)
  automation_state = (Or-Unknown $AutomationState)
  risk_count = (Or-Unknown $RiskCount)
  review_count = (Or-Unknown $ReviewCount)
  monitor_count = (Or-Unknown $MonitorCount)
  client_topology_mode = (Or-Unknown $ClientTopologyMode)
  client_runtime_present = (Or-Unknown $ClientRuntimePresent)
  client_conflict_risk = (Or-Unknown $ClientConflictRisk)
  gateway_matches_router = (Or-Unknown $GatewayMatchesRouter)
  client_http_state = (Or-Unknown $ClientHttpState)
  next_action = $NextAction
}

if ($Json) {
  $Summary | ConvertTo-Json -Depth 3
  exit 0
}

Write-Host "# Edge Health Summary"
Write-Host ""
foreach ($Key in $Summary.Keys) {
  Write-Host "$Key=$($Summary[$Key])"
}
