param(
  [string]$Router = $env:ROUTER,
  [string]$KnownHostsFile = "C:\tmp\home-edge-bootstrap-known-hosts",
  [string]$FetchProxy = "",
  [string]$ConverterBaseUrl = "",
  [string]$ConverterTarget = "",
  [string]$ConverterConfigUrl = "",
  [string]$ApplyPath = "",
  [string]$ReloadCommand = "",
  [switch]$AllowRemoteConverter,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
if (-not $Router) {
  throw "Router is required. Pass -Router <ssh-user>@<router-ip> or set ROUTER."
}

New-Item -ItemType Directory -Force (Split-Path -Parent $KnownHostsFile) | Out-Null
$SshArgs = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ConnectionAttempts=1", "-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=$KnownHostsFile", "--", $Router)

function Quote-Sh {
  param([string]$Value)
  if ($Value.Contains("'")) {
    throw "Converter parameters must not contain a single quote."
  }
  if ($Value -match "[\r\n]") {
    throw "Converter parameters must be a single line."
  }
  return "'$Value'"
}

$Mode = @("SUBSCRIPTION_DRY_RUN=$([int](-not $Apply))")
if ($FetchProxy) { $Mode += "SUBSCRIPTION_FETCH_PROXY=$(Quote-Sh $FetchProxy)" }
if ($ConverterBaseUrl) { $Mode += "SUBSCRIPTION_CONVERTER_BASE_URL=$(Quote-Sh $ConverterBaseUrl)" }
if ($ConverterTarget) { $Mode += "SUBSCRIPTION_CONVERTER_TARGET=$(Quote-Sh $ConverterTarget)" }
if ($ConverterConfigUrl) { $Mode += "SUBSCRIPTION_CONVERTER_CONFIG_URL=$(Quote-Sh $ConverterConfigUrl)" }
if ($ApplyPath) { $Mode += "SUBSCRIPTION_APPLY_PATH=$(Quote-Sh $ApplyPath)" }
if ($ReloadCommand) { $Mode += "SUBSCRIPTION_RELOAD_CMD=$(Quote-Sh $ReloadCommand)" }
if ($AllowRemoteConverter) { $Mode += "SUBSCRIPTION_ALLOW_REMOTE_CONVERTER=1" }

$RemoteScript = "set -e" + [Environment]::NewLine + "$($Mode -join ' ') sh /jffs/scripts/home-edge-update-sub.sh" + [Environment]::NewLine + "tail -n 8 /tmp/update-sub.log 2>/dev/null || true" + [Environment]::NewLine
$Payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($RemoteScript))
$Payload | ssh @SshArgs "base64 -d | sh -s"
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
