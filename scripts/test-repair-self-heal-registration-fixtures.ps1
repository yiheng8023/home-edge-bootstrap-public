$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("home-edge-repair-registration-test-" + [guid]::NewGuid().ToString("N"))
$Bin = Join-Path $Tmp "bin"
$OriginalPath = $env:PATH

function Fail([string]$Message) {
  Write-Host "repair_self_heal_registration_fixture_tests=failed"
  throw $Message
}

try {
  New-Item -ItemType Directory -Force $Bin | Out-Null
  @'
@echo off
more > "%REPAIR_FIXTURE_REMOTE_SCRIPT%"
exit /b %REPAIR_FIXTURE_SSH_EXIT%
'@ | Set-Content -LiteralPath (Join-Path $Bin "ssh.cmd") -Encoding Ascii
  $env:PATH = "$Bin;$OriginalPath"

  $env:REPAIR_FIXTURE_REMOTE_SCRIPT = Join-Path $Tmp "success.remote"
  $env:REPAIR_FIXTURE_SSH_EXIT = "0"
  $SuccessOutput = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "repair-self-heal-registration.ps1") `
    -Router "user@router" `
    -LogPath (Join-Path $Tmp "success.log") `
    -KnownHostsFile (Join-Path $Tmp "success.known-hosts") `
    -NoPause 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Fail "successful fake SSH repair was rejected" }
  if (-not (Select-String -LiteralPath $env:REPAIR_FIXTURE_REMOTE_SCRIPT -SimpleMatch 'sh "$reconciler" --install' -Quiet)) {
    Fail "repair did not request idempotent lifecycle installation"
  }

  $env:REPAIR_FIXTURE_REMOTE_SCRIPT = Join-Path $Tmp "failure.remote"
  $env:REPAIR_FIXTURE_SSH_EXIT = "23"
  $FailureOutput = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "repair-self-heal-registration.ps1") `
    -Router "user@router" `
    -LogPath (Join-Path $Tmp "failure.log") `
    -KnownHostsFile (Join-Path $Tmp "failure.known-hosts") `
    -NoPause 2>&1 | Out-String
  $Status = $LASTEXITCODE
  if ($Status -ne 23) { Fail "SSH failure exit 23 was not preserved (got $Status)" }

  Write-Host "repair_self_heal_registration_fixture_tests=ok"
}
finally {
  $env:PATH = $OriginalPath
  Remove-Item Env:REPAIR_FIXTURE_REMOTE_SCRIPT -ErrorAction SilentlyContinue
  Remove-Item Env:REPAIR_FIXTURE_SSH_EXIT -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
