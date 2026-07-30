param(
  [string]$Router = $env:ROUTER,
  [string]$RemoteDir = "/jffs/home-edge-bootstrap",
  [string]$KnownHostsFile = "C:\tmp\home-edge-bootstrap-known-hosts",
  [switch]$Apply,
  [switch]$Runtime
)

$ErrorActionPreference = "Stop"
if (-not $Router) {
  throw "Router is required. Pass -Router <ssh-user>@<router-ip> or set ROUTER."
}
if ($RemoteDir -notmatch '^/jffs/[A-Za-z0-9_./-]+$' -or $RemoteDir -match '(^|/)\.\.?(/|$)') {
  throw "RemoteDir must be a concrete path under /jffs without unsupported characters or path traversal."
}

$RollbackScript = Join-Path $PSScriptRoot "rollback-router-state.sh"
if (-not (Test-Path -LiteralPath $RollbackScript -PathType Leaf)) {
  throw "Missing $RollbackScript"
}

$KnownHostsDir = Split-Path -Parent $KnownHostsFile
New-Item -ItemType Directory -Force $KnownHostsDir | Out-Null

$Payload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($RollbackScript))
$ApplyFlag = if ($Apply) { "1" } else { "0" }
$RuntimeFlag = if ($Runtime) { "1" } else { "0" }
$RemoteTemplate = @'
set -eu
decode_payload() {
  if which base64 >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | base64 -d
  elif which openssl >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | openssl base64 -d -A
  else
    echo "rollback-merlin: base64 or openssl is required to decode the payload" >&2
    return 1
  fi
}
decode_payload | ROLLBACK_INSTALL_DIR='__REMOTE_DIR__' ROLLBACK_APPLY='__APPLY__' ROLLBACK_RUNTIME='__RUNTIME__' sh -s
'@
$Remote = $RemoteTemplate.Replace("__REMOTE_DIR__", $RemoteDir).Replace("__APPLY__", $ApplyFlag).Replace("__RUNTIME__", $RuntimeFlag)
$SshArgs = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ConnectionAttempts=1", "-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=$KnownHostsFile", "--", $Router, $Remote)

$Payload | ssh @SshArgs
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
