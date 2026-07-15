param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

function Get-StateValue {
  param(
    [string]$Text,
    [string]$Key
  )
  $Match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Key))=(.+)$")
  if ($Match.Success) { return $Match.Groups[1].Value.Trim() }
  return ""
}

function Invoke-Case {
  param(
    [string]$Name,
    [string]$RouterState,
    [string]$FailureHint,
    [string]$ExpectedCheckState
  )

  $env:HOST_SSH_FIXTURE_AGENT_STATE = "identities_loaded"
  $env:HOST_SSH_FIXTURE_DEFAULT_KEY_STATE = "present"
  $env:HOST_SSH_FIXTURE_ROUTER_SSH_STATE = $RouterState
  $env:HOST_SSH_FIXTURE_FAILURE_HINT = $FailureHint

  try {
    $Output = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\check-host-ssh.ps1") -Router "user@192.168.50.1" | Out-String
  }
  finally {
    Remove-Item Env:\HOST_SSH_FIXTURE_AGENT_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:\HOST_SSH_FIXTURE_DEFAULT_KEY_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:\HOST_SSH_FIXTURE_ROUTER_SSH_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:\HOST_SSH_FIXTURE_FAILURE_HINT -ErrorAction SilentlyContinue
  }

  $State = Get-StateValue $Output "host_ssh_check_state"
  if ($State -ne $ExpectedCheckState) {
    throw "$Name expected host_ssh_check_state=$ExpectedCheckState got=$State"
  }
}

Invoke-Case router_ok ok "" ready
Invoke-Case auth_failed failed auth_failed_or_identity_not_loaded router_ssh_failed

Write-Host "host_ssh_fixture_tests=ok"
