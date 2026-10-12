param([string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path)
$ErrorActionPreference = "Stop"
$Fixture = Join-Path ([IO.Path]::GetTempPath()) ("home-edge-installation-ps-" + [guid]::NewGuid().ToString('N'))
$OldSsh = $env:HOME_EDGE_SSH_COMMAND
$OldMode = $env:INSTALLATION_PROBE_MODE
$OldState = $env:INSTALLATION_PROBE_STATE
$OldCapture = $env:INSTALLATION_CAPTURE_FILE
$NativeEnvironment = @{}
$NativeNames = @('INSTALLATION_NATIVE_ROOT', 'INSTALLATION_NATIVE_CAPTURE', 'INSTALLATION_NATIVE_SHELL', 'INSTALLATION_NATIVE_MODE', 'INSTALLATION_NATIVE_TOOLS', 'INSTALLATION_NATIVE_STDERR')
foreach ($Name in $NativeNames) { $NativeEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name) }
try {
  New-Item -ItemType Directory -Path $Fixture | Out-Null
  $Stub = Join-Path $Fixture 'ssh.ps1'
  @'
$Payload = $input | Out-String
$Remote = [string]$args[-1]
if ($Payload -match '(?m)^remote_dir=') {
  if ($Remote -ne 'sh -s') { throw 'Deployment did not use the short remote command' }
  [IO.File]::WriteAllText($env:INSTALLATION_CAPTURE_FILE, $Payload, (New-Object Text.UTF8Encoding($false)))
  $global:LASTEXITCODE = 0
  return
}
if ($env:INSTALLATION_PROBE_MODE -eq 'fail') { $global:LASTEXITCODE = 23; return }
if ($env:INSTALLATION_PROBE_MODE -eq 'malformed') { Write-Output 'project_install_state=not_installed'; $global:LASTEXITCODE = 0; return }
$Target = if ($env:INSTALLATION_PROBE_MODE -eq 'mismatch') { 'user@other' } else { 'user@router' }
$State = if ($env:INSTALLATION_PROBE_STATE) { $env:INSTALLATION_PROBE_STATE } else { 'not_installed' }
$Allowed = if ($State -in @('installed','partial')) { '1' } else { '0' }
$InstallPath = [regex]::Match($Payload, "(?m)^HOME_EDGE_INSTALLATION_DIR='([^']+)'$").Groups[1].Value
Write-Output 'project_install_schema=1'
Write-Output "project_install_router=$Target"
Write-Output "project_install_state=$State"
Write-Output 'project_install_reason=fixture_observation'
Write-Output "project_install_path=$InstallPath"
Write-Output "project_install_replace_allowed=$Allowed"
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath $Stub -Encoding ASCII
  $env:HOME_EDGE_SSH_COMMAND = $Stub
  $env:INSTALLATION_CAPTURE_FILE = Join-Path $Fixture 'deploy-command'
  $KnownHosts = Join-Path $Fixture 'known_hosts'
  $Observer = Join-Path $Repo 'scripts/check-project-installation.ps1'
  $Deploy = Join-Path $Repo 'scripts/deploy-merlin.ps1'
  # A PowerShell script stub does not exercise native stdin framing. Windows
  # PowerShell appends CRLF even when the supplied string already ends in LF.
  # Git Bash tolerates the resulting bare CR; dash matches the router's sh.
  $Sh = (Get-Command sh -CommandType Application -ErrorAction Stop).Source
  $DashCandidates = @(
    (Join-Path (Split-Path -Parent $Sh) 'dash.exe')
    (Join-Path (Split-Path -Parent $Sh) '../usr/bin/dash.exe')
  )
  $Dash = $DashCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
  if (-not $Dash) {
    $Dash = Get-Command dash.exe -CommandType Application -ErrorAction SilentlyContinue |
      ForEach-Object { $_.Source } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
  }
  if (-not $Dash) { throw 'Native framing regression requires the dash shipped with Git for Windows' }
  $Dash = (Resolve-Path -LiteralPath $Dash).Path
  $NativeScript = Join-Path $Fixture 'native-ssh.sh'
  $NativeTransport = Join-Path $Fixture 'native-ssh.cmd'
  $NativeRoot = Join-Path $Fixture 'native-router'
  New-Item -ItemType Directory -Path (Join-Path $NativeRoot 'jffs') | Out-Null
  $env:INSTALLATION_NATIVE_ROOT = '/' + $NativeRoot.Substring(0, 1).ToLowerInvariant() + $NativeRoot.Substring(2).Replace('\', '/')
  $env:INSTALLATION_NATIVE_CAPTURE = (Join-Path $Fixture 'native-payload').Replace('\', '/')
  $env:INSTALLATION_NATIVE_STDERR = (Join-Path $Fixture 'native-stderr').Replace('\', '/')
  $env:INSTALLATION_NATIVE_SHELL = $Dash.Replace('\', '/')
  $NativeTools = Split-Path -Parent $Dash
  $env:INSTALLATION_NATIVE_TOOLS = '/' + $NativeTools.Substring(0, 1).ToLowerInvariant() + $NativeTools.Substring(2).Replace('\', '/')
  [IO.File]::WriteAllText($NativeScript, (@'
#!/bin/sh
# Bind tools inside this transport only; do not change the parent's tar lookup.
PATH="$INSTALLATION_NATIVE_TOOLS:$PATH"
export PATH
cat > "$INSTALLATION_NATIVE_CAPTURE" || exit 1
if [ "$INSTALLATION_NATIVE_MODE" = malformed ]; then
  printf 'project_install_state=not_installed\n'
  exit 0
fi
if [ "$INSTALLATION_NATIVE_MODE" = nonzero ]; then
  suffix='; (exit 23)'
else
  suffix=''
fi
sed -b -e "s|^HOME_EDGE_INSTALLATION_FIXTURE_ROOT=''$|HOME_EDGE_INSTALLATION_FIXTURE_ROOT='$INSTALLATION_NATIVE_ROOT'|" \
    -e "s|^home_edge_inspect_installation$|home_edge_inspect_installation$suffix|" \
    "$INSTALLATION_NATIVE_CAPTURE" | "$INSTALLATION_NATIVE_SHELL" -s 2>"$INSTALLATION_NATIVE_STDERR"
exit $?
'@).Replace("`r", "") + "`n", [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText($NativeTransport, ('@"' + $Dash + '" "%~dp0native-ssh.sh"' + "`r`n"), [Text.Encoding]::ASCII)
  $NativeHosts = @((Get-Command powershell -CommandType Application -ErrorAction Stop).Source)
  $Pwsh = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue
  if ($Pwsh) { $NativeHosts += $Pwsh.Source }
  foreach ($NativeHost in $NativeHosts) {
    foreach ($NativeMode in @('ready', 'malformed', 'nonzero', 'unknown')) {
      $env:INSTALLATION_NATIVE_MODE = $NativeMode
      if ($NativeMode -eq 'unknown') { New-Item -ItemType Directory -Path (Join-Path $NativeRoot 'jffs/home-edge-bootstrap') | Out-Null }
      $Output = & $NativeHost -NoProfile -ExecutionPolicy Bypass -File $Observer -Router user@router -KnownHostsFile $KnownHosts -SshCommand $NativeTransport | Out-String
      if ($NativeMode -eq 'ready') {
        if ($LASTEXITCODE -ne 0 -or $Output -notmatch 'project_install_state=not_installed' -or $Output -notmatch 'project_install_replace_allowed=0') {
          $NativeFailure = if (Test-Path -LiteralPath $env:INSTALLATION_NATIVE_STDERR) { [IO.File]::ReadAllText($env:INSTALLATION_NATIVE_STDERR) } else { 'Native transport did not produce its stderr record.' }
          throw "Native stdin framing failed: $NativeHost`n$Output`n$NativeFailure"
        }
      } else {
        $Reason = if ($NativeMode -eq 'malformed') { 'malformed_observation' } elseif ($NativeMode -eq 'nonzero') { 'probe_failed' } else { 'foreign_project_directory' }
        if ($LASTEXITCODE -eq 0 -or $Output -notmatch 'project_install_state=unknown' -or $Output -notmatch "project_install_reason=$Reason" -or $Output -notmatch 'project_install_replace_allowed=0') { throw "Native invalid observation was trusted: $NativeHost/$NativeMode`n$Output" }
      }
      if ($NativeMode -eq 'unknown') { Remove-Item -LiteralPath (Join-Path $NativeRoot 'jffs/home-edge-bootstrap') }
    }
    Write-Host "project_installation_native_framing=ok host=$NativeHost"
  }
  foreach ($Mode in @('ready', 'fail', 'malformed', 'mismatch')) {
    $env:INSTALLATION_PROBE_MODE = $Mode
    $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Observer -Router user@router -KnownHostsFile $KnownHosts | Out-String
    if ($Mode -eq 'ready') {
      if ($LASTEXITCODE -ne 0 -or $Output -notmatch 'project_install_state=not_installed') { throw 'Fresh observation failed' }
    } elseif ($LASTEXITCODE -eq 0 -or $Output -notmatch 'project_install_state=unknown') { throw "Invalid observation was trusted: $Mode" }
  }
  $env:INSTALLATION_PROBE_MODE = 'ready'
  foreach ($State in @('installed', 'partial', 'unknown')) {
    $env:INSTALLATION_PROBE_STATE = $State
    $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Deploy -Router user@router -KnownHostsFile $KnownHosts -Apply | Out-String
    if ($LASTEXITCODE -eq 0 -or (Test-Path -LiteralPath $env:INSTALLATION_CAPTURE_FILE)) { throw "Default write reached SSH transfer: $State" }
  }
  $env:INSTALLATION_PROBE_STATE = 'installed'
  foreach ($Wrong in @('', 'replace', 'REPLACE ')) {
    $WrongArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Deploy, '-Router', 'user@router', '-KnownHostsFile', $KnownHosts, '-ReplaceProject', '-Apply')
    if ($Wrong) { $WrongArgs += @('-ProjectConfirmation', $Wrong) }
    $ErrorActionPreference = 'Continue'
    $Output = & powershell @WrongArgs 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0 -or (Test-Path -LiteralPath $env:INSTALLATION_CAPTURE_FILE)) { throw 'Inexact replacement confirmation reached a transfer' }
  }
  $Plan = & powershell -NoProfile -ExecutionPolicy Bypass -File $Deploy -Router user@router -KnownHostsFile $KnownHosts | Out-String
  if ($LASTEXITCODE -ne 0 -or $Plan -notmatch 'project_replacement_required=1' -or $Plan -notmatch 'installation_probe=read_only') { throw 'Existing installation plan failed' }
  $RuntimeNames = @('BOOTSTRAP_INSTALL_RUNTIME', 'BOOTSTRAP_REPLACE_RUNTIME', 'BOOTSTRAP_REPLACE_CORE')
  $RuntimePrevious = @{}
  try {
    foreach ($Name in $RuntimeNames) { $RuntimePrevious[$Name] = [Environment]::GetEnvironmentVariable($Name); [Environment]::SetEnvironmentVariable($Name, '1') }
    $Plan = & powershell -NoProfile -ExecutionPolicy Bypass -File $Deploy -Router user@router -KnownHostsFile $KnownHosts -ProjectOnly | Out-String
    foreach ($Expected in @('install_runtime=0', 'replace_runtime=0', 'replace_core=0', 'include_bundle=0', 'runtime_assets_effect=preserve', 'integration_effect=project_managed_configuration_may_change')) {
      if ($LASTEXITCODE -ne 0 -or $Plan -notmatch ('(?m)^' + [regex]::Escape($Expected) + '\r?$')) { throw "ProjectOnly honored ambient runtime authority: $Expected" }
    }
    $ErrorActionPreference = 'Continue'
    $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Deploy -Router user@router -KnownHostsFile $KnownHosts -ProjectOnly -InstallRuntime 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0) { throw 'ProjectOnly accepted a conflicting explicit switch' }
  } finally { foreach ($Name in $RuntimeNames) { [Environment]::SetEnvironmentVariable($Name, $RuntimePrevious[$Name]) } }
  # No remote code is executed. The transport records the actual locked template.
  $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Deploy -Router user@router -KnownHostsFile $KnownHosts -Apply -ReplaceProject -ProjectConfirmation REPLACE | Out-String
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $env:INSTALLATION_CAPTURE_FILE)) { throw 'Explicit project replacement was not forwarded' }
  $Remote = Get-Content -LiteralPath $env:INSTALLATION_CAPTURE_FILE -Raw
  if ($Remote -notmatch 'home_edge_require_project_replacement "1" "REPLACE"' -or $Remote.Contains('__INSTALLATION_LIBRARY__')) { throw 'Replacement permission or observer missing from actual locked template' }
  if ($Remote.IndexOf('home_edge_require_project_replacement "1" "REPLACE"') -lt $Remote.IndexOf("acquire_deploy_lock`n")) { throw 'Fresh guard is before the writer lock' }
  if ($Remote.IndexOf('home_edge_require_project_replacement "1" "REPLACE"') -gt $Remote.IndexOf('mkdir "$staging"', $Remote.IndexOf("acquire_deploy_lock`n"))) { throw 'Fresh guard is after staging mutation' }
  $env:INSTALLATION_PROBE_STATE = 'not_installed'
  $Output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Deploy -Router user@router -KnownHostsFile $KnownHosts -RemoteDir /jffs/custom -ProjectOnly -Apply | Out-String
  if ($LASTEXITCODE -ne 0) { throw 'Custom target cannot reach isolated transport' }
  $Remote = Get-Content -LiteralPath $env:INSTALLATION_CAPTURE_FILE -Raw
  if ($Remote -notmatch 'remote_dir="/jffs/custom"' -or $Remote -notmatch 'HOME_EDGE_WRITE_LOCK_HELD=1 BOOTSTRAP_INSTALL_DIR="\$remote_dir" BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 sh bootstrap.sh' -or
      $Remote -notmatch 'BOOTSTRAP_INSTALL_RUNTIME=0 BOOTSTRAP_INSTALL_DIR="\$remote_dir" sh "\$remote_dir/bootstrap.sh"') { throw 'Actual PowerShell custom deployment/restoration template lost its bound installation target' }
  Write-Host 'project_installation_fixture_tests_ps=ok'
} finally {
  $env:HOME_EDGE_SSH_COMMAND = $OldSsh
  $env:INSTALLATION_PROBE_MODE = $OldMode
  $env:INSTALLATION_PROBE_STATE = $OldState
  $env:INSTALLATION_CAPTURE_FILE = $OldCapture
  foreach ($Name in $NativeNames) { [Environment]::SetEnvironmentVariable($Name, $NativeEnvironment[$Name]) }
  if (([IO.Path]::GetFullPath($Fixture)).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $Fixture -Recurse -Force }
}
