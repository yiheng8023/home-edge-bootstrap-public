param(
  [string]$Router = $env:ROUTER,
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
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

function Invoke-Captured {
  param([scriptblock]$Block)
  $global:LASTEXITCODE = 0
  $Output = & $Block 2>&1 | Out-String
  $ExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
  return [pscustomobject]@{ Output = $Output; ExitCode = $ExitCode }
}

function Get-FixtureResult {
  param([string]$Name)
  $Output = [Environment]::GetEnvironmentVariable("DOCTOR_FIXTURE_${Name}_OUTPUT")
  if ($null -eq $Output) { return $null }
  $ExitText = [Environment]::GetEnvironmentVariable("DOCTOR_FIXTURE_${Name}_EXIT")
  $ExitCode = 0
  if ($ExitText) { $ExitCode = [int]$ExitText }
  return [pscustomobject]@{ Output = $Output; ExitCode = $ExitCode }
}

function Use-FixtureOrRun {
  param(
    [string]$Name,
    [scriptblock]$Block
  )
  $Fixture = Get-FixtureResult $Name
  if ($null -ne $Fixture) { return $Fixture }
  return Invoke-Captured $Block
}

function Get-WorkingDirectoryState {
  param([string]$RepoPath)
  $RepoFull = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepoPath).Path).TrimEnd("\", "/")
  $CwdFull = [System.IO.Path]::GetFullPath((Get-Location).Path).TrimEnd("\", "/")
  $Comparison = if ($IsWindows -or $env:OS -eq "Windows_NT") {
    [System.StringComparison]::OrdinalIgnoreCase
  }
  else {
    [System.StringComparison]::Ordinal
  }
  if ([string]::Equals($CwdFull, $RepoFull, $Comparison)) { return "repo_root" }
  if ($CwdFull.StartsWith($RepoFull + [System.IO.Path]::DirectorySeparatorChar, $Comparison)) { return "inside_repo" }
  return "outside_repo"
}


$CloseoutScript = Join-Path $PSScriptRoot "verify-closeout.ps1"
$NoWallScript = Join-Path $PSScriptRoot "check-no-wall-readiness.ps1"
$HostSshScript = Join-Path $PSScriptRoot "check-host-ssh.ps1"
$EdgeHealthScript = Join-Path $PSScriptRoot "check-edge-health.ps1"

$Repository = Use-FixtureOrRun "REPOSITORY" {
  powershell -NoProfile -ExecutionPolicy Bypass -File $CloseoutScript -Repo $Repo
}
$NoWall = Use-FixtureOrRun "NO_WALL" {
  powershell -NoProfile -ExecutionPolicy Bypass -File $NoWallScript -Repo $Repo
}

$HostSsh = [pscustomobject]@{
  Output = "host_ssh_check_state=not_checked`nrouter_ssh_state=not_checked"
  ExitCode = 0
}
$EdgeHealth = [pscustomobject]@{
  Output = "edge_health_state=not_checked`nnext_action=provide router target and rerun"
  ExitCode = 0
}

if ($Router) {
  $HostSsh = Use-FixtureOrRun "HOST_SSH" {
    powershell -NoProfile -ExecutionPolicy Bypass -File $HostSshScript -Router $Router
  }
  $EdgeHealth = Use-FixtureOrRun "EDGE_HEALTH" {
    powershell -NoProfile -ExecutionPolicy Bypass -File $EdgeHealthScript -Router $Router
  }
}

$RepositoryState = Get-StateValue $Repository.Output "closeout_state"
$WorkingDirectoryState = Get-WorkingDirectoryState -RepoPath $Repo
$LocalToolsState = Get-StateValue $NoWall.Output "status"
$BundleState = Get-StateValue $NoWall.Output "bundle_state"
$HostSshState = Get-StateValue $HostSsh.Output "host_ssh_check_state"
$RouterSshState = Get-StateValue $HostSsh.Output "router_ssh_state"
$SshFailureHint = Get-StateValue $HostSsh.Output "ssh_failure_hint"

$EdgeHealthState = Get-StateValue $EdgeHealth.Output "edge_health_state"
$ProxyState = Get-StateValue $EdgeHealth.Output "proxy_state"
$SubscriptionState = Get-StateValue $EdgeHealth.Output "subscription_state"
$AutomationState = Get-StateValue $EdgeHealth.Output "automation_state"
$ClientTopologyMode = Get-StateValue $EdgeHealth.Output "client_topology_mode"
$ClientRuntimePresent = Get-StateValue $EdgeHealth.Output "client_runtime_present"
$ClientConflictRisk = Get-StateValue $EdgeHealth.Output "client_conflict_risk"
$EdgeNextAction = Get-StateValue $EdgeHealth.Output "next_action"

$DoctorState = "needs_attention"
$NextAction = "inspect doctor output"
$NextActionCommand = ".\scripts\doctor.ps1 -Router <ssh-user>@<router-ip>"

if ($Repository.ExitCode -ne 0 -or $RepositoryState -ne "ready") {
  $DoctorState = "repository_attention"
  $NextAction = "fix repository closeout structure before operating the router"
  $NextActionCommand = ".\scripts\verify-closeout.ps1"
}
elseif ($NoWall.ExitCode -ne 0 -or $LocalToolsState -ne "tools_ready") {
  $DoctorState = "host_tools_attention"
  $NextAction = "install or repair local tools before router work"
  $NextActionCommand = ".\scripts\check-no-wall-readiness.ps1"
}
elseif (-not $Router) {
  $DoctorState = "local_ready_router_not_checked"
  $NextAction = "provide the router SSH target and rerun doctor"
  $NextActionCommand = ".\scripts\doctor.ps1 -Router <ssh-user>@<router-ip>"
}
elseif ($HostSsh.ExitCode -ne 0 -or $HostSshState -ne "ready") {
  $DoctorState = "router_connection_attention"
  $NextAction = "fix host SSH or router SSH reachability"
  $NextActionCommand = ".\scripts\check-host-ssh.ps1 -Router $Router"
}
elseif ($EdgeHealthState -eq "router_managed" -and $EdgeNextAction -eq "none") {
  $DoctorState = "ready"
  $NextAction = "none"
  $NextActionCommand = "none"
}
else {
  $DoctorState = "router_attention"
  $NextAction = if ($EdgeNextAction) { $EdgeNextAction } else { "inspect edge health and guide-router output" }
  $NextActionCommand = ".\scripts\check-edge-health.ps1 -Router $Router"
}

$Summary = [ordered]@{
  doctor_state = $DoctorState
  repository_state = (Or-Unknown $RepositoryState)
  working_directory_state = (Or-Unknown $WorkingDirectoryState)
  local_tools_state = (Or-Unknown $LocalToolsState)
  bundle_state = (Or-Unknown $BundleState)
  router_target_state = $(if ($Router) { "provided" } else { "missing" })
  host_ssh_check_state = (Or-Unknown $HostSshState)
  router_ssh_state = (Or-Unknown $RouterSshState)
  ssh_failure_hint = (Or-Unknown $SshFailureHint)
  edge_health_state = (Or-Unknown $EdgeHealthState)
  proxy_state = (Or-Unknown $ProxyState)
  subscription_state = (Or-Unknown $SubscriptionState)
  automation_state = (Or-Unknown $AutomationState)
  client_topology_mode = (Or-Unknown $ClientTopologyMode)
  client_runtime_present = (Or-Unknown $ClientRuntimePresent)
  client_conflict_risk = (Or-Unknown $ClientConflictRisk)
  next_action = $NextAction
  next_action_command = $NextActionCommand
}

if ($Json) {
  $Summary | ConvertTo-Json -Depth 3
  if ($DoctorState -eq "repository_attention" -or $DoctorState -eq "host_tools_attention" -or $DoctorState -eq "router_connection_attention") {
    exit 1
  }
  exit 0
}

Write-Host "# Home Edge Doctor"
Write-Host ""
Write-Host "This is a read-only entrypoint. It does not deploy, reload, or change router settings."
Write-Host ""
foreach ($Key in $Summary.Keys) {
  Write-Host "$Key=$($Summary[$Key])"
}

if ($DoctorState -eq "repository_attention" -or $DoctorState -eq "host_tools_attention" -or $DoctorState -eq "router_connection_attention") {
  exit 1
}
exit 0
