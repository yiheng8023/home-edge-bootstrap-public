param(
  [string]$Router = $env:ROUTER,
  [string]$RemoteDir = "/jffs/home-edge-bootstrap",
  [string]$KnownHostsFile = "C:\tmp\home-edge-bootstrap-known-hosts",
  [string]$SshCommand = $(if ($env:HOME_EDGE_SSH_COMMAND) { $env:HOME_EDGE_SSH_COMMAND } else { "ssh" })
)
$ErrorActionPreference = "Stop"
if ($Router -notmatch '^[A-Za-z0-9_.-]+@[A-Za-z0-9][A-Za-z0-9.-]*$' -or $Router -match '@\.|\.\.|\.$') { throw "Invalid router target." }
if ($RemoteDir -notmatch '^/jffs/[A-Za-z0-9_.-]+$' -or $RemoteDir -in @('/jffs/.', '/jffs/..')) { throw "Invalid remote directory." }
function Write-Unknown([string]$Reason) {
  Write-Output "project_install_schema=1"
  Write-Output "project_install_router=$Router"
  Write-Output "project_install_state=unknown"
  Write-Output "project_install_reason=$Reason"
  Write-Output "project_install_path=$RemoteDir"
  Write-Output "project_install_replace_allowed=0"
}
try {
  # Keep the project's selected-target trust history; never modify global .ssh.
  $KnownHostsDirectory = Split-Path -Parent $KnownHostsFile
  if ($KnownHostsDirectory) { New-Item -ItemType Directory -Force -Path $KnownHostsDirectory | Out-Null }
  $Library = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../adapters/merlin/lib/installation-state.sh") -Raw
  $Payload = ($Library + "`nHOME_EDGE_INSTALLATION_DIR='$RemoteDir'`nHOME_EDGE_INSTALLATION_ROUTER='$Router'`nHOME_EDGE_INSTALLATION_FIXTURE_ROOT=''`nhome_edge_inspect_installation`n").Replace("`r", "")
  $SshArgs = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', '-o', 'ConnectionAttempts=1', '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$KnownHostsFile", '--', $Router, 'sh -s')
  $global:LASTEXITCODE = 0
  $Lines = @($Payload | & $SshCommand @SshArgs 2>$null)
  if ($LASTEXITCODE -ne 0) { Write-Unknown "probe_failed"; exit 1 }
} catch { Write-Unknown "probe_failed"; exit 1 }
$Values = @{}
$Malformed = $Lines.Count -ne 6
foreach ($Line in $Lines) {
  if ([string]$Line -notmatch '^([a-z_]+)=([A-Za-z0-9_@./-]+)$' -or $Values.ContainsKey($Matches[1])) { $Malformed = $true; continue }
  $Values[$Matches[1]] = $Matches[2]
}
if ($Malformed -or $Values.project_install_schema -cne '1' -or $Values.project_install_path -cne $RemoteDir -or
    $Values.project_install_state -cnotin @('installed', 'not_installed', 'partial', 'unknown') -or
    $Values.project_install_reason -cnotmatch '^[a-z0-9_]+$' -or $Values.project_install_replace_allowed -cnotin @('0', '1') -or
    ($Values.project_install_state -in @('unknown', 'not_installed') -and $Values.project_install_replace_allowed -ne '0')) {
  Write-Unknown 'malformed_observation'; exit 1
}
if ($Values.project_install_router -cne $Router) { Write-Unknown 'target_mismatch'; exit 1 }
$Lines | Write-Output
if ($Values.project_install_state -eq 'unknown') { exit 1 }
