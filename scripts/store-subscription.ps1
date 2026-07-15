param(
  [string]$Router = $env:ROUTER,
  [string]$RemotePath = "/jffs/home-edge-bootstrap/SUBSCRIPTION.local",
  [string]$KnownHostsFile = "C:\tmp\home-edge-bootstrap-known-hosts",
  [string]$SubscriptionUrl = ""
)

$ErrorActionPreference = "Stop"
if (-not $Router) {
  throw "Router is required. Pass -Router <ssh-user>@<router-ip> or set ROUTER."
}

if (-not $SubscriptionUrl) {
  $secure = Read-Host "Paste provider subscription URL" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $SubscriptionUrl = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

$SubscriptionUrl = $SubscriptionUrl.Trim()
if ($SubscriptionUrl -match "[\r\n]") {
  throw "Subscription URL must be a single line."
}
if ($SubscriptionUrl -notmatch "^https?://") {
  throw "Subscription URL must start with http:// or https://."
}
if ($RemotePath -notmatch "^/jffs/" -or $RemotePath -match "['`"]") {
  throw "RemotePath must be an absolute /jffs/ path without quotes."
}
if ($RemotePath -notmatch '^/jffs/[A-Za-z0-9_./-]+$' -or $RemotePath -match '(^|/)\.\.?(/|$)' -or $RemotePath.EndsWith('/')) {
  throw "RemotePath must be a safe file path below /jffs."
}

New-Item -ItemType Directory -Force (Split-Path -Parent $KnownHostsFile) | Out-Null
$SshArgs = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ConnectionAttempts=1", "-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=$KnownHostsFile", "--", $Router)
$RemoteCommand = 'set -e; dir=$(dirname "' + $RemotePath + '"); mkdir -p "$dir"; umask 077; base64 -d > "' + $RemotePath + '"; chmod 600 "' + $RemotePath + '"; bytes=$(wc -c < "' + $RemotePath + '"); echo subscription_file="' + $RemotePath + '"; echo subscription_bytes="$bytes"'
$Encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SubscriptionUrl + "`n"))

$Encoded | ssh @SshArgs $RemoteCommand
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
