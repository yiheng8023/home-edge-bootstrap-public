param(
  [string]$Router = $env:ROUTER,
  [string]$LogPath = "C:\tmp\home-edge-repair-self-heal-registration.log",
  [string]$KnownHostsFile = "C:\tmp\home-edge-bootstrap-known-hosts",
  [int]$SshConnectTimeoutSec = 8,
  [switch]$NoPause
)

$ErrorActionPreference = "Stop"
if (-not $Router) {
  throw "Router is required. Pass -Router <ssh-user>@<router-ip> or set ROUTER."
}

New-Item -ItemType Directory -Force (Split-Path -Parent $LogPath) | Out-Null
New-Item -ItemType Directory -Force (Split-Path -Parent $KnownHostsFile) | Out-Null

$RemoteScript = @'
set -eu
reconciler=/jffs/scripts/home-edge-reconcile-self-heal.sh
[ -x "$reconciler" ] || { echo "repair-self-heal-registration: ERROR: lifecycle reconciler is not deployed" >&2; exit 1; }
sh "$reconciler" --install
'@
$SshArgs = @(
  "-o", "BatchMode=yes",
  "-o", "ConnectTimeout=$SshConnectTimeoutSec",
  "-o", "ConnectionAttempts=1",
  "-o", "StrictHostKeyChecking=accept-new",
  "-o", "UserKnownHostsFile=$KnownHostsFile",
  "--", $Router
)

$ExitCode = 1
$Failure = $null
Start-Transcript -Path $LogPath -Force
try {
  $RemoteScript | ssh @SshArgs 'tr -d "\r" | sh -s'
  $ExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 1 }
  Write-Host ""
  Write-Host "Lifecycle registration repair finished with exit code: $ExitCode"
}
catch {
  $Failure = $_
  Write-Host ""
  Write-Host "Lifecycle registration repair failed:"
  Write-Host $_
}
finally {
  Stop-Transcript
  Write-Host ""
  Write-Host "Repair log: $LogPath"
  if (-not $NoPause) { Read-Host "Press Enter to close" }
}

if ($Failure) { exit 1 }
if ($ExitCode -ne 0) { exit $ExitCode }
