param(
  [string]$Router = $env:ROUTER,
  [string]$KnownHostsFile = 'C:\tmp\home-edge-bootstrap-known-hosts',
  [int]$SshConnectTimeoutSec = 8,
  [switch]$Apply,
  [string]$Confirmation = '',
  [switch]$NoPause
)

$ErrorActionPreference = "Stop"
function Test-RouterTarget([string]$Target) {
  if ($Target -notmatch '^[A-Za-z0-9_.-]+@[A-Za-z0-9][A-Za-z0-9.-]*$') { return $false }
  $HostPart = ($Target -split '@', 2)[1]
  -not ($HostPart.StartsWith('.') -or $HostPart.EndsWith('.') -or $HostPart.Contains('..'))
}
function Stop-Usage([string]$Message) {
  [Console]::Error.WriteLine("decommission-merlin: ERROR: $Message")
  exit 2
}

if (-not $Router) { Stop-Usage "Router is required. Pass -Router <ssh-user>@<router-ip> or set ROUTER." }
if (-not (Test-RouterTarget $Router)) { Stop-Usage "invalid router target: $Router" }
if ($Apply -and $Confirmation -cne 'DECOMMISSION') {
  [Console]::Error.WriteLine('decommission-merlin: ERROR: -Apply requires -Confirmation DECOMMISSION')
  exit 2
}
if (-not $Apply -and $Confirmation) { Stop-Usage "-Confirmation is valid only with -Apply" }
if ($SshConnectTimeoutSec -le 0) { Stop-Usage "SshConnectTimeoutSec must be positive" }

$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SourceScripts = @("migrate-router-state.sh", "decommission-router-state.sh")
foreach ($Name in $SourceScripts) {
  $Path = Join-Path $PSScriptRoot $Name
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).LinkType) {
    [Console]::Error.WriteLine("decommission-merlin: ERROR: missing reviewed source: $Path")
    exit 1
  }
}
$TarCommand = Get-Command tar.exe -ErrorAction SilentlyContinue
if (-not $TarCommand) { [Console]::Error.WriteLine("decommission-merlin: ERROR: tar.exe is required"); exit 1 }
$SshCommand = $(if ($env:HOME_EDGE_SSH_COMMAND) { $env:HOME_EDGE_SSH_COMMAND } else { "ssh" })
if (-not (Get-Command $SshCommand -ErrorAction SilentlyContinue)) { [Console]::Error.WriteLine("decommission-merlin: ERROR: ssh is required"); exit 1 }

$KnownHostsDir = Split-Path -Parent $KnownHostsFile
if (-not $KnownHostsDir) { Stop-Usage "KnownHostsFile must include a parent directory" }
$Archive = Join-Path $env:TEMP ("home-edge-decommission-" + [Guid]::NewGuid().ToString("N") + ".tgz")
$ExitCode = 1
$ApplyValue = $(if ($Apply) { "1" } else { "0" })
$ConfirmationValue = $(if ($Apply) { "DECOMMISSION" } else { "" })
$RemoteTemplate = @'
set -eu
work=/tmp/home-edge-decommission.$$
cleanup() { rm -rf "$work"; }
handle_signal() { cleanup; trap - EXIT; exit 130; }
trap cleanup EXIT
trap handle_signal HUP INT TERM
mkdir -m 700 "$work"
base64 -d | tar -xzf - -C "$work"
[ -f "$work/migrate-router-state.sh" ] && [ ! -L "$work/migrate-router-state.sh" ]
[ -f "$work/decommission-router-state.sh" ] && [ ! -L "$work/decommission-router-state.sh" ]
HOME_EDGE_STATE_MIGRATOR="$work/migrate-router-state.sh" \
DECOMMISSION_APPLY=__APPLY__ \
DECOMMISSION_CONFIRMATION=__CONFIRMATION__ \
sh "$work/decommission-router-state.sh"
'@
$Remote = $RemoteTemplate.Replace("__APPLY__", $ApplyValue).Replace("__CONFIRMATION__", $ConfirmationValue)
$SshArgs = @(
  "-o", "BatchMode=yes",
  "-o", "ConnectTimeout=$SshConnectTimeoutSec",
  "-o", "ConnectionAttempts=1",
  "-o", "StrictHostKeyChecking=accept-new",
  "-o", "UserKnownHostsFile=$KnownHostsFile",
  "--", $Router, $Remote
)

try {
  New-Item -ItemType Directory -Force $KnownHostsDir | Out-Null
  & $TarCommand.Source -C $PSScriptRoot -czf $Archive @SourceScripts
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Archive -PathType Leaf)) { throw "failed to build decommission payload" }
  $Payload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Archive))
  $Payload | & $SshCommand @SshArgs
  $ExitCode = $(if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE })
}
catch {
  [Console]::Error.WriteLine("decommission-merlin: ERROR: $($_.Exception.Message)")
  $ExitCode = 1
}
finally {
  Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
}

if (-not $NoPause) { [void](Read-Host "Press Enter to close") }
exit $ExitCode
