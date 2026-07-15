param(
  [Parameter(Mandatory = $true)]
  [string]$Router,
  [switch]$ClientConfirmed,
  [switch]$RunClientCheck,
  [string]$ClientCheckUrl = "https://cp.cloudflare.com/generate_204",
  [switch]$AcceptRuntimeImportedSubscription,
  [switch]$DashboardConfirmed,
  [switch]$AcceptClientRuntime,
  [string]$Repo = ""
)

$ErrorActionPreference = "Stop"

if (-not $Repo) {
  $Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-StateValue {
  param(
    [string]$Text,
    [string]$Key
  )
  $Match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Key))=(.+)$")
  if ($Match.Success) {
    return $Match.Groups[1].Value.Trim()
  }
  return ""
}

function Write-Gate {
  param(
    [string]$Name,
    [string]$Value
  )
  Write-Host "$Name=$Value"
}

function Get-RouterHost {
  param([string]$RouterValue)
  if ($RouterValue -match "@([^@]+)$") {
    return $Matches[1]
  }
  return $RouterValue
}

function Run-Capture {
  param([scriptblock]$Block)
  $Output = & $Block 2>&1 | Out-String
  return $Output
}

$VerifyScript = Join-Path $Repo "scripts\verify-closeout.ps1"
$GuideScript = Join-Path $Repo "scripts\guide-router.ps1"
$StatusScript = Join-Path $Repo "scripts\check-router-status.ps1"
$ClientTopologyScript = Join-Path $Repo "scripts\check-client-topology.ps1"

Write-Host "# Installation Closeout Check"
Write-Host ""

$RepositoryOutput = Run-Capture { powershell -NoProfile -ExecutionPolicy Bypass -File $VerifyScript -Repo $Repo }
$RepositoryOk = ($RepositoryOutput -match "(?m)^closeout_state=ready")

$GuideOutput = Run-Capture { powershell -NoProfile -ExecutionPolicy Bypass -File $GuideScript -Router $Router -NoPause }
$GuideExit = $LASTEXITCODE

$StatusOutput = Run-Capture { powershell -NoProfile -ExecutionPolicy Bypass -File $StatusScript -Router $Router -NoPause }
$StatusExit = $LASTEXITCODE

$DeviceState = Get-StateValue $GuideOutput "device_state"
$AdminState = Get-StateValue $GuideOutput "admin_state"
$BaselineState = Get-StateValue $GuideOutput "baseline_state"
$ProxyState = Get-StateValue $GuideOutput "proxy_state"
$RuntimeState = Get-StateValue $GuideOutput "runtime_state"
$RuntimeProcessState = Get-StateValue $GuideOutput "runtime_process_state"
$ControllerObservationState = Get-StateValue $GuideOutput "controller_observation_state"
$ControllerAuthState = Get-StateValue $GuideOutput "controller_auth_state"
$SelfHealRegistrationState = Get-StateValue $GuideOutput "self_heal_registration_state"
$SelfHealBootHookState = Get-StateValue $GuideOutput "self_heal_boot_hook_state"
$SubscriptionState = Get-StateValue $GuideOutput "subscription_state"
$SubscriptionConsumptionState = Get-StateValue $GuideOutput "subscription_consumption_state"
$DashboardConfigState = Get-StateValue $GuideOutput "dashboard_config_state"
$DashboardReachabilityState = Get-StateValue $GuideOutput "dashboard_reachability_state"
$AutomationState = Get-StateValue $GuideOutput "automation_state"
$RiskCount = Get-StateValue $GuideOutput "risk_count"
$ReviewCount = Get-StateValue $GuideOutput "review_count"
$MonitorCount = Get-StateValue $GuideOutput "monitor_count"

$RepositoryGate = if ($RepositoryOk) { "pass" } else { "fail" }
$RouterGate = if (
  $GuideExit -eq 0 -and
  $DeviceState -eq "ssh_reachable" -and
  $AdminState -eq "jffs_scripts_ready" -and
  ($BaselineState -eq "reviewed" -or $BaselineState -eq "reviewed_with_monitoring") -and
  $RiskCount -eq "0" -and
  $ReviewCount -eq "0"
) { "pass" } else { "fail" }

$RuntimeGate = if (
  $GuideExit -eq 0 -and
  $StatusExit -eq 0 -and
  $ProxyState -eq "verified" -and
  $RuntimeState -eq "running" -and
  $RuntimeProcessState -eq "running" -and
  $ControllerObservationState -eq "ready" -and
  ($ControllerAuthState -eq "authenticated" -or $ControllerAuthState -eq "not_required") -and
  $SelfHealRegistrationState -eq "ready" -and
  $SelfHealBootHookState -eq "ready" -and
  $AutomationState -eq "live_managed"
) { "pass" } else { "fail" }

$RouteEvidenceProbeId = Get-StateValue $StatusOutput "route_evidence_probe_id"
$RouteEvidenceIdentity = Get-StateValue $StatusOutput "route_evidence_identity"
$RouteEvidenceClassification = Get-StateValue $StatusOutput "route_evidence_classification"
$RouteEvidenceVerificationState = Get-StateValue $StatusOutput "route_evidence_verification_state"
$RouteGate = if ($RouteEvidenceProbeId -and $RouteEvidenceIdentity -and $RouteEvidenceClassification -in @("reachable", "region_match") -and $RouteEvidenceVerificationState -eq "pass") { "pass" } else { "fail" }

$SubscriptionGate = "fail"
if ($SubscriptionConsumptionState -eq "runtime_profile_matches_cache") {
  $SubscriptionGate = "pass"
}
elseif ($SubscriptionState -eq "missing") {
  $SubscriptionGate = "missing"
}
elseif ($AcceptRuntimeImportedSubscription -and ($SubscriptionConsumptionState -eq "manual_runtime_import_unverified" -or $SubscriptionConsumptionState -eq "cache_only_unverified" -or $SubscriptionConsumptionState -eq "profile_file_matches_cache")) {
  $SubscriptionGate = "accepted_manual_boundary"
}
else {
  $SubscriptionGate = "consumption_unverified"
}

$DashboardGate = "fail"
$DashboardEvidence = "unverified"
if ($DashboardConfigState -eq "not_configured") {
  $DashboardGate = "not_applicable"
  $DashboardEvidence = "not_applicable"
}
elseif ($DashboardConfigState -eq "configured" -and $DashboardReachabilityState -eq "ready") {
  $DashboardGate = "pass"
  $DashboardEvidence = "observed_ready"
}
elseif ($DashboardConfigState -eq "configured" -and $DashboardReachabilityState -eq "unverified" -and $DashboardConfirmed) {
  $DashboardGate = "pass"
  $DashboardEvidence = "user_confirmed"
}
elseif ($DashboardConfigState -eq "configured") {
  $DashboardGate = "reachability_unverified"
}
else {
  $DashboardGate = "configuration_unknown"
}

$ClientEvidence = ""
$ClientGate = "manual_required"
if ($ClientConfirmed) {
  $ClientGate = "pass"
  $ClientEvidence = "user_confirmed"
}
elseif ($RunClientCheck) {
  $ClientTopologyOutput = Run-Capture { powershell -NoProfile -ExecutionPolicy Bypass -File $ClientTopologyScript -Router $Router -ClientCheckUrl $ClientCheckUrl }
  $ClientTopologyMode = Get-StateValue $ClientTopologyOutput "client_topology_mode"
  $ClientRuntimePresent = Get-StateValue $ClientTopologyOutput "client_runtime_present"
  $GatewayMatchesRouter = Get-StateValue $ClientTopologyOutput "gateway_matches_router"
  $ClientHttpState = Get-StateValue $ClientTopologyOutput "client_http_state"
  $ClientConflictRisk = Get-StateValue $ClientTopologyOutput "client_conflict_risk"
  $ClientEvidence = "topology=$ClientTopologyMode runtime_present=$ClientRuntimePresent gateway_matches_router=$GatewayMatchesRouter http=$ClientHttpState conflict_risk=$ClientConflictRisk"

  if ($ClientRuntimePresent -eq "1") {
    if ($AcceptClientRuntime) {
      $ClientGate = "accepted_client_runtime"
    }
    else {
      $ClientGate = "client_runtime_present"
    }
  }
  elseif ($ClientRuntimePresent -ne "0") {
    $ClientGate = "client_runtime_unknown"
  }
  elseif ($GatewayMatchesRouter -ne "yes") {
    $ClientGate = "fail"
  }
  else {
    switch -Regex ($ClientHttpState) {
      "^ok:" { $ClientGate = "pass"; break }
      default { $ClientGate = "fail" }
    }
  }
}

$AllTechnicalPass = (
  $RepositoryGate -eq "pass" -and
  $RouterGate -eq "pass" -and
  $RuntimeGate -eq "pass" -and
  $RouteGate -eq "pass"
)
$SubscriptionAccepted = ($SubscriptionGate -eq "pass" -or $SubscriptionGate -eq "accepted_manual_boundary")
$ClientAccepted = ($ClientGate -eq "pass" -or $ClientGate -eq "accepted_client_runtime")
$DashboardAccepted = ($DashboardGate -eq "pass" -or $DashboardGate -eq "not_applicable")
$FinalAccepted = ($AllTechnicalPass -and $SubscriptionAccepted -and $ClientAccepted -and $DashboardAccepted)
$StrongPass = ($FinalAccepted -and $SubscriptionGate -eq "pass" -and $ClientGate -eq "pass" -and ($DashboardGate -eq "pass" -or $DashboardGate -eq "not_applicable"))

$CloseoutState = "partial"
if ($StrongPass) {
  $CloseoutState = "pass"
}
elseif ($FinalAccepted) {
  $CloseoutState = "accepted_boundary"
}
elseif (-not $AllTechnicalPass) {
  $CloseoutState = "fail"
}

Write-Gate "repository_gate" $RepositoryGate
Write-Gate "router_gate" $RouterGate
Write-Gate "runtime_gate" $RuntimeGate
Write-Gate "route_gate" $RouteGate
Write-Gate "subscription_gate" $SubscriptionGate
Write-Gate "dashboard_gate" $DashboardGate
Write-Gate "dashboard_evidence" $DashboardEvidence
Write-Gate "client_gate" $ClientGate
Write-Gate "installation_closeout_state" $CloseoutState
Write-Host ""

Write-Gate "device_state" $(if ($DeviceState) { $DeviceState } else { "unknown" })
Write-Gate "admin_state" $(if ($AdminState) { $AdminState } else { "unknown" })
Write-Gate "baseline_state" $(if ($BaselineState) { $BaselineState } else { "unknown" })
Write-Gate "proxy_state" $(if ($ProxyState) { $ProxyState } else { "unknown" })
Write-Gate "runtime_state" $(if ($RuntimeState) { $RuntimeState } else { "unknown" })
Write-Gate "runtime_process_state" $(if ($RuntimeProcessState) { $RuntimeProcessState } else { "unknown" })
Write-Gate "controller_observation_state" $(if ($ControllerObservationState) { $ControllerObservationState } else { "unknown" })
Write-Gate "controller_auth_state" $(if ($ControllerAuthState) { $ControllerAuthState } else { "unknown" })
Write-Gate "self_heal_registration_state" $(if ($SelfHealRegistrationState) { $SelfHealRegistrationState } else { "unknown" })
Write-Gate "self_heal_boot_hook_state" $(if ($SelfHealBootHookState) { $SelfHealBootHookState } else { "unknown" })
Write-Gate "subscription_state" $(if ($SubscriptionState) { $SubscriptionState } else { "unknown" })
Write-Gate "subscription_consumption_state" $(if ($SubscriptionConsumptionState) { $SubscriptionConsumptionState } else { "unknown" })
Write-Gate "dashboard_config_state" $(if ($DashboardConfigState) { $DashboardConfigState } else { "unknown" })
Write-Gate "dashboard_reachability_state" $(if ($DashboardReachabilityState) { $DashboardReachabilityState } else { "unknown" })
Write-Gate "automation_state" $(if ($AutomationState) { $AutomationState } else { "unknown" })
Write-Gate "route_evidence_probe_id" $(if ($RouteEvidenceProbeId) { $RouteEvidenceProbeId } else { "unknown" })
Write-Gate "route_evidence_identity" $(if ($RouteEvidenceIdentity) { $RouteEvidenceIdentity } else { "unknown" })
Write-Gate "route_evidence_classification" $(if ($RouteEvidenceClassification) { $RouteEvidenceClassification } else { "unknown" })
Write-Gate "route_evidence_verification_state" $(if ($RouteEvidenceVerificationState) { $RouteEvidenceVerificationState } else { "unknown" })
Write-Gate "monitor_count" $(if ($MonitorCount) { $MonitorCount } else { "unknown" })
if ($ClientEvidence) {
  Write-Gate "client_evidence" $ClientEvidence
}
Write-Host ""

if ($CloseoutState -eq "pass" -or $CloseoutState -eq "accepted_boundary") {
  Write-Host "next_action=none"
}
elseif (-not $AllTechnicalPass) {
  Write-Host "next_action=inspect guide-router and check-router-status output, then fix the earliest failing gate"
}
elseif ($SubscriptionGate -eq "consumption_unverified" -or $SubscriptionGate -eq "missing") {
  Write-Host "next_action=prove the validated cache is the live runtime profile, or rerun with -AcceptRuntimeImportedSubscription only when manual ShellCrash import is intentionally accepted and separately verified"
}
elseif ($DashboardGate -eq "reachability_unverified") {
  Write-Host "next_action=verify the configured native dashboard is reachable, then rerun with -DashboardConfirmed to record that verified human evidence"
}
elseif ($ClientGate -eq "manual_required") {
  Write-Host "next_action=confirm from a client device that the configured probe target or another strict external target opens through this router, or rerun with -RunClientCheck on a computer whose default gateway is this router"
}
elseif ($ClientGate -eq "client_runtime_present") {
  Write-Host "next_action=temporarily disable the local client proxy/TUN or make its policy intentionally equivalent, then rerun; use -AcceptClientRuntime only for an intentional fallback or hybrid topology"
}
elseif ($ClientGate -eq "client_runtime_unknown") {
  Write-Host "next_action=rerun the read-only client topology check from a host where proxy, DNS, and route inspection are available; unknown evidence cannot pass pure router verification"
}
elseif ($ClientGate -eq "fail") {
  Write-Host "next_action=run the client check on a computer whose default gateway is this router, or confirm manually from a client device and rerun with -ClientConfirmed"
}
else {
  Write-Host "next_action=inspect guide-router and check-router-status output, then fix the earliest failing gate"
}

if ($CloseoutState -eq "pass" -or $CloseoutState -eq "accepted_boundary") {
  exit 0
}
exit 1
