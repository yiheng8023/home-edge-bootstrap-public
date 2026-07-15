param(
  [string]$Router = $env:ROUTER,
  [string]$RemoteDir = "/jffs/home-edge-bootstrap",
  [string]$LogPath = "C:\tmp\home-edge-deploy.log",
  [string]$KnownHostsFile = "C:\tmp\home-edge-bootstrap-known-hosts",
  [switch]$IncludeBundle,
  [switch]$InstallRuntime,
  [switch]$ReplaceRuntime,
  [switch]$NoPause,
  [switch]$Apply
)

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force (Split-Path -Parent $LogPath) | Out-Null

Start-Transcript -Path $LogPath -Force
try {
  if (-not $Router) {
    throw "Router is required. Pass -Router <ssh-user>@<router-ip> or set ROUTER."
  }
  Set-Location (Resolve-Path (Join-Path $PSScriptRoot ".."))
  if ($Apply) {
    & (Join-Path $PSScriptRoot "deploy-merlin.ps1") -Router $Router -RemoteDir $RemoteDir -KnownHostsFile $KnownHostsFile -IncludeBundle:$IncludeBundle -InstallRuntime:$InstallRuntime -ReplaceRuntime:$ReplaceRuntime -Apply
  } else {
    & (Join-Path $PSScriptRoot "deploy-merlin.ps1") -Router $Router -RemoteDir $RemoteDir -KnownHostsFile $KnownHostsFile -IncludeBundle:$IncludeBundle -InstallRuntime:$InstallRuntime -ReplaceRuntime:$ReplaceRuntime
  }
  $exitCode = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }
  Write-Host ""
  Write-Host "Deploy finished with exit code: $exitCode"
}
catch {
  Write-Host ""
  Write-Host "Deploy failed:"
  Write-Host $_
}
finally {
  Stop-Transcript
  Write-Host ""
  Write-Host "Deploy log: $LogPath"
  if (-not $NoPause) {
    Read-Host "Press Enter to close"
  }
}
