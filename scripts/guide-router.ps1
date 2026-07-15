param(
  [string]$Router = $env:ROUTER,
  [string]$AuditLogPath = "C:\tmp\home-edge-router-guide-audit.log",
  [string]$KnownHostsFile = "C:\tmp\home-edge-bootstrap-known-hosts",
  [switch]$Json,
  [switch]$NoPause
)

$ErrorActionPreference = "Stop"
if (-not $Router) {
  throw "Router is required. Pass -Router <ssh-user>@<router-ip> or set ROUTER."
}

function Get-StateValue {
  param([string]$Key)
  if (-not (Test-Path -LiteralPath $AuditLogPath)) { return $null }
  $line = Get-Content -LiteralPath $AuditLogPath | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
  if (-not $line) { return $null }
  return ($line -replace "^$Key=", "")
}

function Or-Unknown {
  param([string]$Value)
  if ($Value) { return $Value }
  return "unknown"
}

$AuditScript = Join-Path $PSScriptRoot "audit-router-baseline.ps1"
$AuditOutput = ""
$AuditExit = 0

if ($env:GUIDE_ROUTER_FIXTURE_AUDIT_OUTPUT) {
  New-Item -ItemType Directory -Force (Split-Path -Parent $AuditLogPath) | Out-Null
  Set-Content -LiteralPath $AuditLogPath -Value $env:GUIDE_ROUTER_FIXTURE_AUDIT_OUTPUT -Encoding UTF8
}
else {
  $AuditArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $AuditScript, "-Router", $Router, "-LogPath", $AuditLogPath, "-KnownHostsFile", $KnownHostsFile, "-NoPause")
  $AuditOutput = powershell @AuditArgs 2>&1 | Out-String
  $AuditExit = $LASTEXITCODE

  if (-not $Json -and $AuditOutput) {
    Write-Host $AuditOutput.TrimEnd()
  }
  if ($AuditExit -ne 0) {
    if ($Json) {
      [ordered]@{
        guide_state = "audit_failed"
        next_action_code = "fix_router_reachability"
        next_action_command = ".\scripts\guide-router.ps1 -Router $Router -NoPause"
        audit_log_path = $AuditLogPath
        audit_exit_code = [string]$AuditExit
        audit_error = $AuditOutput.Trim()
      } | ConvertTo-Json -Depth 3
    }
    else {
      Write-Host ""
      Write-Host "Guide stopped: audit failed with exit code $AuditExit."
      Write-Host "Fix SSH/router reachability, then rerun this guide."
    }
    exit $AuditExit
  }
}

$DeviceState = Get-StateValue "device_state"
$FirmwareState = Get-StateValue "firmware_state"
$AdminState = Get-StateValue "admin_state"
$BaselineState = Get-StateValue "baseline_state"
$ProxyState = Get-StateValue "proxy_state"
$RuntimeState = Get-StateValue "runtime_state"
$RuntimeProcessState = Get-StateValue "runtime_process_state"
$ControllerState = Get-StateValue "controller_state"
$ControllerAuthState = Get-StateValue "controller_auth_state"
$ControllerObservationState = Get-StateValue "controller_observation_state"
$SelfHealRegistrationState = Get-StateValue "self_heal_registration_state"
$SelfHealBootHookState = Get-StateValue "self_heal_boot_hook_state"
$LifecycleReconcilerState = Get-StateValue "lifecycle_reconciler_state"
$SubscriptionState = Get-StateValue "subscription_state"
$SubscriptionConsumptionState = Get-StateValue "subscription_consumption_state"
$DashboardConfigState = Get-StateValue "dashboard_config_state"
$DashboardReachabilityState = Get-StateValue "dashboard_reachability_state"
$AutomationState = Get-StateValue "automation_state"
$RiskCount = Get-StateValue "risk_count"
$ReviewCount = Get-StateValue "review_count"
$MonitorCount = Get-StateValue "monitor_count"

if (-not $DeviceState) {
  if ($Json) {
    [ordered]@{
      guide_state = "unreadable_audit"
      next_action_code = "inspect_audit_log"
      next_action_command = ".\scripts\guide-router.ps1 -Router $Router -NoPause"
      audit_log_path = $AuditLogPath
    } | ConvertTo-Json -Depth 3
  }
  else {
    Write-Error "Audit log did not contain a readable machine state: $AuditLogPath"
  }
  exit 1
}

$NextActionCode = "inspect_audit_log"
$NextActionCommand = ".\scripts\guide-router.ps1 -Router $Router -NoPause"
$NextActionText = "State is incomplete or unknown. Inspect the audit log, then rerun:"

if ($AdminState -ne "jffs_scripts_ready") {
  $NextActionCode = "enable_router_prereqs"
  $NextActionCommand = ".\scripts\guide-router.ps1 -Router $Router -NoPause"
  $NextActionText = "Open the router web UI, enable LAN SSH and JFFS custom scripts/configs, then rerun:"
}
elseif ($BaselineState -eq "risky") {
  $NextActionCode = "resolve_action_findings"
  $NextActionCommand = ".\scripts\guide-router.ps1 -Router $Router -NoPause"
  $NextActionText = "Resolve ACTION findings from the audit, then rerun:"
}
elseif ($BaselineState -eq "needs_review") {
  $NextActionCode = "review_baseline_findings"
  $NextActionCommand = ".\scripts\guide-router.ps1 -Router $Router -NoPause"
  $NextActionText = "Review REVIEW findings from the audit, decide the intended policy, then rerun:"
}
elseif ($LifecycleReconcilerState -eq "absent") {
  $NextActionCode = "deploy_plan"
  $NextActionCommand = ".\scripts\deploy-merlin.ps1 -Router $Router"
  $NextActionText = "Upgrade the existing installation to deploy the lifecycle reconciler, then re-check state:"
}
elseif ($ProxyState -ne "absent" -and ($SelfHealRegistrationState -ne "ready" -or $SelfHealBootHookState -ne "ready")) {
  $NextActionCode = "repair_self_heal_registration"
  $NextActionCommand = ".\scripts\repair-self-heal-registration.ps1 -Router $Router -NoPause"
  $NextActionText = "Restore the project-owned boot hook and self-heal scheduler, then re-check state:"
}
elseif ($RuntimeState -eq "authentication_blocked") {
  $NextActionCode = "configure_controller_auth"
  $NextActionCommand = ".\scripts\check-router-status.ps1 -Router $Router -NoPause"
  $NextActionText = "Configure the matching Mihomo controller secret in the router-local policy, then re-check without exposing it:"
}
elseif ($RuntimeState -eq "controller_unreachable") {
  $NextActionCode = "inspect_or_start_proxy_runtime"
  $NextActionCommand = ".\scripts\check-router-status.ps1 -Router $Router -NoPause"
  $NextActionText = "Inspect ShellCrash/Mihomo runtime state and start or repair it through its adapter or native interface, then re-check:"
}
elseif ($AutomationState -eq "live_managed") {
  if ($SubscriptionState -eq "missing" -or $SubscriptionState -eq "runtime_imported") {
    $NextActionCode = "store_subscription_for_managed_switching"
    $NextActionCommand = ".\scripts\store-subscription.ps1 -Router $Router"
    $NextActionText = "The router is live-managed. For scripted provider switching later, store the provider subscription on the router first:"
  }
  else {
    $NextActionCode = "monitor_live_managed"
    $NextActionCommand = ".\scripts\check-router-status.ps1 -Router $Router -NoPause"
    $NextActionText = "The router baseline and proxy path are already live-managed. Check status when needed:"
  }
}
elseif ($ProxyState -eq "absent") {
  $NextActionCode = "deploy_plan"
  $NextActionCommand = ".\scripts\deploy-merlin.ps1 -Router $Router"
  $NextActionText = "Run deploy plan first:"
}
elseif ($ProxyState -eq "policy_deployed" -or $ProxyState -eq "self_heal_installed") {
  $NextActionCode = "store_or_import_subscription"
  $NextActionCommand = ".\scripts\store-subscription.ps1 -Router $Router"
  $NextActionText = "Store and refresh the provider subscription, or import/start it in ShellCrash, then check status:"
}
elseif ($ProxyState -eq "api_reachable") {
  $NextActionCode = "inspect_self_heal_dry_run"
  $NextActionCommand = ".\scripts\check-router-status.ps1 -Router $Router -NoPause"
  $NextActionText = "Run status and inspect DRY-RUN self-heal logs:"
}
elseif ($ProxyState -eq "verified") {
  $NextActionCode = "enable_live_self_heal"
  $NextActionCommand = ".\scripts\enable-live-self-heal.ps1 -Router $Router -NoPause"
  $NextActionText = "The router baseline and proxy path are usable. Confirm live self-heal when desired:"
}

$Summary = [ordered]@{
  guide_state = "ready"
  device_state = (Or-Unknown $DeviceState)
  firmware_state = (Or-Unknown $FirmwareState)
  admin_state = (Or-Unknown $AdminState)
  baseline_state = (Or-Unknown $BaselineState)
  proxy_state = (Or-Unknown $ProxyState)
  runtime_state = (Or-Unknown $RuntimeState)
  runtime_process_state = (Or-Unknown $RuntimeProcessState)
  controller_state = (Or-Unknown $ControllerState)
  controller_auth_state = (Or-Unknown $ControllerAuthState)
  controller_observation_state = (Or-Unknown $ControllerObservationState)
  self_heal_registration_state = (Or-Unknown $SelfHealRegistrationState)
  self_heal_boot_hook_state = (Or-Unknown $SelfHealBootHookState)
  lifecycle_reconciler_state = (Or-Unknown $LifecycleReconcilerState)
  subscription_state = (Or-Unknown $SubscriptionState)
  subscription_consumption_state = (Or-Unknown $SubscriptionConsumptionState)
  dashboard_config_state = (Or-Unknown $DashboardConfigState)
  dashboard_reachability_state = (Or-Unknown $DashboardReachabilityState)
  automation_state = (Or-Unknown $AutomationState)
  risk_count = (Or-Unknown $RiskCount)
  review_count = (Or-Unknown $ReviewCount)
  monitor_count = (Or-Unknown $MonitorCount)
  next_action_code = $NextActionCode
  next_action_command = $NextActionCommand
  audit_log_path = $AuditLogPath
}

if ($Json) {
  $Summary | ConvertTo-Json -Depth 3
  exit 0
}

Write-Host ""
Write-Host "## Guided State Summary"
foreach ($Key in $Summary.Keys) {
  Write-Host "$Key=$($Summary[$Key])"
}

Write-Host ""
Write-Host "## Suggested Next Command"
Write-Host $NextActionText
Write-Host "  $NextActionCommand"
if ($NextActionCode -eq "deploy_plan") {
  Write-Host "Then apply only after the plan looks right:"
  Write-Host "  .\scripts\deploy-merlin.ps1 -Router $Router -Apply"
}
elseif ($NextActionCode -eq "store_or_import_subscription") {
  Write-Host "  .\scripts\refresh-subscription.ps1 -Router $Router"
  Write-Host "  .\scripts\check-router-status.ps1 -Router $Router -NoPause"
}
elseif ($NextActionCode -eq "enable_live_self_heal") {
  Write-Host "Then rerun:"
  Write-Host "  .\scripts\check-router-status.ps1 -Router $Router -NoPause"
}

if (-not $NoPause) {
  Read-Host "Press Enter to close"
}
