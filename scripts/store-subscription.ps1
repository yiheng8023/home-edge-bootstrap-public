param(
  [string]$Router = $env:ROUTER,
  [string]$RemotePath = "/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local",
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
$RemoteTemplate = @'
set -eu
decode_payload() {
  if which base64 >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | base64 -d
  elif which openssl >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | openssl base64 -d -A
  else
    echo "store-subscription: base64 or openssl is required to decode the payload" >&2
    return 1
  fi
}
remote_path="__REMOTE_PATH__"
dir=$(dirname "$remote_path")
mkdir -p "$dir"
umask 077
tmp_path="${remote_path}.tmp.$$"
cleanup() {
  rm -f "$tmp_path" 2>/dev/null || true
}
handle_signal() {
  cleanup
  trap - EXIT
  exit 130
}
trap cleanup EXIT
trap handle_signal HUP INT TERM
[ ! -L "$remote_path" ] || {
  echo "store-subscription: refusing symbolic-link target" >&2
  exit 1
}
decode_payload >"$tmp_path"
[ -s "$tmp_path" ] || {
  echo "store-subscription: decoded payload is empty" >&2
  exit 1
}
chmod 600 "$tmp_path"
mv -f "$tmp_path" "$remote_path"
trap - EXIT HUP INT TERM
bytes=$(wc -c <"$remote_path")
echo "subscription_file=$remote_path"
echo "subscription_bytes=$bytes"
'@
$RemoteCommand = $RemoteTemplate.Replace("__REMOTE_PATH__", $RemotePath)
$Encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SubscriptionUrl + "`n"))

$Encoded | ssh @SshArgs $RemoteCommand
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
