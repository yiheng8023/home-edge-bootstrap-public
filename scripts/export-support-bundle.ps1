param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$Router = $env:ROUTER,
  [string]$OutputDir = "C:\tmp\home-edge-support-bundles",
  [string]$KnownHostsFile = "C:\tmp\home-edge-bootstrap-known-hosts",
  [string]$SshCommand = $(if ($env:HOME_EDGE_SSH_COMMAND) { $env:HOME_EDGE_SSH_COMMAND } else { "ssh" })
)

$ErrorActionPreference = "Stop"
$PowerShellExe = (Get-Command powershell.exe -ErrorAction Stop).Source

function Redact-SupportText {
  param([string]$Text)
  $Redacted = $Text
  $Redacted = $Redacted -replace "-----BEGIN [^-]+ PRIVATE KEY-----[\s\S]*?-----END [^-]+ PRIVATE KEY-----", "REDACTED_PRIVATE_KEY"
  $Redacted = $Redacted -replace "(?i)(RunAs User|Username)\s*[:=]\s*[^`r`n]+", '$1=REDACTED'
  $Redacted = $Redacted -replace "(?i)(Machine)\s*:\s*[^\(`r`n]+", '$1: REDACTED '
  $Redacted = $Redacted -replace "C:\\Users\\[^\\`r`n]+", "C:\Users\REDACTED"
  $Redacted = $Redacted -replace "(?m)^([bcdlps-][rwxStTs-]{9}\s+\d+\s+)\S+(\s+\S+\s+)", '${1}REDACTED_USER${2}'
  $Redacted = $Redacted -replace "(?i)\bgit@[A-Za-z0-9._-]+:[^\s`"'<>]+", "git@REDACTED_GIT_REMOTE"
  $Redacted = $Redacted -replace "\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b", "REDACTED_EMAIL"
  $Redacted = $Redacted -replace "\b[A-Za-z0-9._%+-]+@((10|127)\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b", "REDACTED_USER@REDACTED_LAN_IP"
  $Redacted = $Redacted -replace "\b((10|127)\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b", "REDACTED_LAN_IP"
  $Redacted = $Redacted -replace "(?i)(subscription(_url)?|password|passwd|token|secret|authorization|api[-_ ]?key|uuid|username)\s*[:=]\s*[^`r`n]+", '$1=REDACTED'
  $Redacted = $Redacted -replace "(?i)(https?|ss|ssr|vmess|vless|trojan|hysteria2?)://[^\s`"'<>]+", '$1://REDACTED_URL'
  $Redacted = $Redacted -replace "\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", "REDACTED_UUID"
  $Redacted = $Redacted -replace "\b[A-Za-z0-9+/=_-]{48,}\b", "REDACTED_TOKEN"
  $Redacted
}

function Write-RedactedFile {
  param(
    [string]$Path,
    [string]$Text
  )
  $Encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, (Redact-SupportText $Text), $Encoding)
}

function Capture-Command {
  param(
    [string]$Name,
    [scriptblock]$Command,
    [string]$Directory
  )
  $Path = Join-Path $Directory $Name
  try {
    $Output = & $Command 2>&1 | Out-String
    Write-RedactedFile -Path $Path -Text $Output
  }
  catch {
    Write-RedactedFile -Path $Path -Text ("capture_failed=$Name" + [Environment]::NewLine + ($_ | Out-String))
  }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$Stamp = "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$PID"
$WorkDir = Join-Path $OutputDir "home-edge-support-$Stamp"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$Manifest = @"
# Home Edge Support Bundle
created_at=$(Get-Date -Format o)
repo=$Repo
router_supplied=$([bool]$Router)

This bundle is intended for diagnosis. It excludes subscription files, node lists,
runtime caches, private keys, and bundle binaries. Captured text is redacted before
it is written.
"@
Write-RedactedFile -Path (Join-Path $WorkDir "manifest.txt") -Text $Manifest

Capture-Command -Name "git-status.txt" -Directory $WorkDir -Command {
  Set-Location -LiteralPath $Repo
  git status --short --branch
}
Capture-Command -Name "git-head.txt" -Directory $WorkDir -Command {
  Set-Location -LiteralPath $Repo
  git rev-parse HEAD
  git remote -v
}
Capture-Command -Name "tracked-files.txt" -Directory $WorkDir -Command {
  Set-Location -LiteralPath $Repo
  git ls-files | Where-Object {
    $_ -notmatch '(^|/)(bundle|cache|backups)/' -and
    $_ -notmatch 'SUBSCRIPTION|subscription.*[.](yaml|txt|local)$' -and
    $_ -notmatch '[.](key|pem|log)$'
  }
}
Capture-Command -Name "closeout.txt" -Directory $WorkDir -Command {
  & (Join-Path $PSScriptRoot "verify-closeout.ps1") -Repo $Repo
}
Capture-Command -Name "no-wall-readiness.txt" -Directory $WorkDir -Command {
  & (Join-Path $PSScriptRoot "check-no-wall-readiness.ps1") -Repo $Repo
}
Capture-Command -Name "doctor.txt" -Directory $WorkDir -Command {
  & (Join-Path $PSScriptRoot "doctor.ps1") -Router $Router -Repo $Repo
}
Capture-Command -Name "host-ssh.txt" -Directory $WorkDir -Command {
  & (Join-Path $PSScriptRoot "check-host-ssh.ps1") -Router $Router -KnownHostsFile $KnownHostsFile
}
Capture-Command -Name "client-topology.txt" -Directory $WorkDir -Command {
  & (Join-Path $PSScriptRoot "check-client-topology.ps1") -Router $Router
}

if ($Router) {
  Capture-Command -Name "edge-health.txt" -Directory $WorkDir -Command {
    & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "check-edge-health.ps1") -Router $Router -KnownHostsFile $KnownHostsFile
  }
  Capture-Command -Name "router-status.txt" -Directory $WorkDir -Command {
    & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "check-router-status.ps1") -Router $Router -KnownHostsFile $KnownHostsFile -SshCommand $SshCommand -NoPause -NoLog
  }
}
else {
  Write-RedactedFile -Path (Join-Path $WorkDir "edge-health.txt") -Text "edge_health_state=skipped_no_router"
  Write-RedactedFile -Path (Join-Path $WorkDir "router-status.txt") -Text "router_status=skipped_no_router"
}

function Get-SafeLifecycleValue {
  param(
    [string]$Text,
    [string]$Name,
    [string[]]$Allowed,
    [string]$Default = "unavailable"
  )
  $Match = [regex]::Match($Text, "(?m)^" + [regex]::Escape($Name) + "=([a-z0-9_.-]+)\r?$")
  if ($Match.Success -and $Allowed -contains $Match.Groups[1].Value) { return $Match.Groups[1].Value }
  $Default
}

$RouterStatusText = Get-Content -LiteralPath (Join-Path $WorkDir "router-status.txt") -Raw
$StableSchema = Get-SafeLifecycleValue -Text $RouterStatusText -Name "stable_state_schema" -Allowed @("1", "missing", "invalid")
$StableSubscription = Get-SafeLifecycleValue -Text $RouterStatusText -Name "stable_subscription_state" -Allowed @("present", "absent", "unavailable")
$StablePolicy = Get-SafeLifecycleValue -Text $RouterStatusText -Name "stable_policy_state" -Allowed @("present", "absent", "unavailable")
$CompatibilityBridge = Get-SafeLifecycleValue -Text $RouterStatusText -Name "compatibility_bridge_state" -Allowed @("present", "absent", "drift")
$LifecycleReport = @(
  "stable_state_root=/jffs/home-edge-bootstrap-state",
  "stable_state_schema=$StableSchema",
  "stable_subscription_state=$StableSubscription",
  "stable_policy_state=$StablePolicy",
  "compatibility_bridge_state=$CompatibilityBridge"
) -join [Environment]::NewLine
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $WorkDir "lifecycle-state.txt"), ($LifecycleReport + [Environment]::NewLine), $Utf8NoBom)

$Archive = "$WorkDir.zip"
if (Test-Path -LiteralPath $Archive) {
  Remove-Item -LiteralPath $Archive -Force
}
Compress-Archive -Path (Join-Path $WorkDir "*") -DestinationPath $Archive -Force

Write-Host "# Support Bundle"
Write-Host "support_bundle_state=ready"
Write-Host "support_bundle_dir=$WorkDir"
Write-Host "support_bundle_archive=$Archive"
