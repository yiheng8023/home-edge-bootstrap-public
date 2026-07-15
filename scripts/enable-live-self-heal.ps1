param(
  [string]$Router = $env:ROUTER,
  [string]$LogPath = "C:\tmp\home-edge-enable-live-self-heal.log",
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

$RouterScript = Join-Path $PSScriptRoot "enable-live-self-heal-router.sh"
if (-not (Test-Path -LiteralPath $RouterScript -PathType Leaf)) {
  throw "Missing $RouterScript"
}

$SshArgs = @(
  "-o", "BatchMode=yes",
  "-o", "ConnectTimeout=$SshConnectTimeoutSec",
  "-o", "ConnectionAttempts=1",
  "-o", "StrictHostKeyChecking=accept-new",
  "-o", "UserKnownHostsFile=$KnownHostsFile",
  "--",
  $Router
)
$Payload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($RouterScript))
$ExitCode = 1
$Failure = $null

Start-Transcript -Path $LogPath -Force
try {
  $Payload | ssh @SshArgs "base64 -d | sh -s"
  $ExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 1 }
  Write-Host ""
  Write-Host "Enable live self-heal finished with exit code: $ExitCode"
}
catch {
  $Failure = $_
  Write-Host ""
  Write-Host "Enable live self-heal failed:"
  Write-Host $_
}
finally {
  Stop-Transcript
  Write-Host ""
  Write-Host "Enable log: $LogPath"
  if (-not $NoPause) {
    Read-Host "Press Enter to close"
  }
}

if ($Failure) {
  exit 1
}
if ($ExitCode -ne 0) {
  exit $ExitCode
}
