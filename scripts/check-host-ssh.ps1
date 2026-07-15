param(
  [string]$Router = $env:ROUTER,
  [string]$KnownHostsFile = "C:\tmp\home-edge-bootstrap-known-hosts",
  [int]$TimeoutSec = 5
)

$ErrorActionPreference = "Continue"

function Write-Kv {
  param([string]$Key, [string]$Value)
  if (-not $Value) { $Value = "unknown" }
  Write-Host "$Key=$Value"
}

function Get-DefaultKeyState {
  $HomeDir = $HOME
  if (-not $HomeDir) { return "unknown" }
  $Names = @("id_ed25519", "id_ecdsa", "id_rsa")
  foreach ($Name in $Names) {
    if (Test-Path -LiteralPath (Join-Path $HomeDir ".ssh\$Name") -PathType Leaf) {
      return "present"
    }
  }
  return "missing"
}

function Get-AgentState {
  if (-not (Get-Command ssh-add -ErrorAction SilentlyContinue)) { return "ssh_add_missing" }
  $Output = & ssh-add -l 2>&1 | Out-String
  $Code = $LASTEXITCODE
  if ($Code -eq 0) { return "identities_loaded" }
  if ($Output -match "no identities|The agent has no identities") { return "no_identities" }
  if ($Output -match "Could not open|Error connecting|No such file") { return "agent_unavailable" }
  return "unknown"
}

function Get-FailureHint {
  param([string]$Text)
  if ($Text -match "Permission denied") { return "auth_failed_or_identity_not_loaded" }
  if ($Text -match "Connection timed out|Operation timed out|No route to host|Network is unreachable") { return "router_unreachable" }
  if ($Text -match "Connection refused") { return "router_ssh_disabled_or_wrong_port" }
  if ($Text -match "Could not resolve hostname") { return "router_name_unresolved" }
  return "inspect_ssh_error"
}

$SshClientState = "present"
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  $SshClientState = "missing"
}

$AgentState = if ($env:HOST_SSH_FIXTURE_AGENT_STATE) { $env:HOST_SSH_FIXTURE_AGENT_STATE } else { Get-AgentState }
$DefaultKeyState = if ($env:HOST_SSH_FIXTURE_DEFAULT_KEY_STATE) { $env:HOST_SSH_FIXTURE_DEFAULT_KEY_STATE } else { Get-DefaultKeyState }
$RouterTargetState = if ($Router) { "provided" } else { "missing" }
$RouterSshState = "skipped_no_router"
$FailureHint = ""

if ($SshClientState -eq "missing") {
  $RouterSshState = "skipped_no_ssh_client"
  $FailureHint = "install_openssh"
}
elseif ($env:HOST_SSH_FIXTURE_ROUTER_SSH_STATE) {
  $RouterSshState = $env:HOST_SSH_FIXTURE_ROUTER_SSH_STATE
  $FailureHint = $env:HOST_SSH_FIXTURE_FAILURE_HINT
}
elseif ($Router) {
  New-Item -ItemType Directory -Force (Split-Path -Parent $KnownHostsFile) | Out-Null
  $SshArgs = @(
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=$TimeoutSec",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "UserKnownHostsFile=$KnownHostsFile",
    "--",
    $Router,
    "echo router-ssh-ok"
  )
  $Output = & ssh @SshArgs 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0 -and $Output -match "router-ssh-ok") {
    $RouterSshState = "ok"
  }
  else {
    $RouterSshState = "failed"
    $FailureHint = Get-FailureHint $Output
  }
}

$CheckState = "ready"
if ($SshClientState -eq "missing") {
  $CheckState = "missing_ssh_client"
}
elseif ($RouterSshState -eq "failed") {
  $CheckState = "router_ssh_failed"
}
elseif ($RouterSshState -eq "skipped_no_router") {
  $CheckState = "host_only_ready"
}

Write-Host "# Host SSH Check"
Write-Host ""
Write-Kv "host_ssh_check_state" $CheckState
Write-Kv "ssh_client_state" $SshClientState
Write-Kv "ssh_agent_state" $AgentState
Write-Kv "default_key_state" $DefaultKeyState
Write-Kv "router_target_state" $RouterTargetState
Write-Kv "router_ssh_state" $RouterSshState
Write-Kv "ssh_failure_hint" $FailureHint
