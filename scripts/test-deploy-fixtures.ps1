param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [switch]$LocalRuntimeArchiveOnly
)
$ErrorActionPreference = "Stop"
$Deploy = Join-Path $Repo "scripts\deploy-merlin.ps1"
$FixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("home-edge-deploy-ps-" + [guid]::NewGuid().ToString("N"))
$FixtureBundle = Join-Path $FixtureRoot "bundle"
$PreviousBundleDir = $env:DEPLOY_BUNDLE_DIR
$PreviousSsh = $env:HOME_EDGE_SSH_COMMAND
$NativeNames = @('DEPLOY_NATIVE_TOOLS', 'DEPLOY_NATIVE_ROOT', 'DEPLOY_NATIVE_FAIL_AT', 'DEPLOY_NATIVE_ROLLBACK_FAIL')
$NativePrevious = @{}
foreach ($Name in $NativeNames) { $NativePrevious[$Name] = [Environment]::GetEnvironmentVariable($Name) }
try {
  New-Item -ItemType Directory -Path $FixtureRoot | Out-Null
  $ProbeStub = Join-Path $FixtureRoot 'ssh.ps1'
  @'
$null = $input | Out-String
Write-Output 'project_install_schema=1'
Write-Output 'project_install_router=user@router'
Write-Output 'project_install_state=not_installed'
Write-Output 'project_install_reason=no_project_artifacts'
Write-Output 'project_install_path=/jffs/home-edge-bootstrap'
Write-Output 'project_install_replace_allowed=0'
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath $ProbeStub -Encoding ASCII
  $env:HOME_EDGE_SSH_COMMAND = $ProbeStub
  $KnownHosts = Join-Path $FixtureRoot 'known_hosts'
  $Plan = & powershell -NoProfile -ExecutionPolicy Bypass -File $Deploy -Router user@router -KnownHostsFile $KnownHosts 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0 -or $Plan -notmatch 'deploy_state=plan' -or $Plan -notmatch 'installation_probe=read_only') { throw "PowerShell read-only deploy plan failed" }
  New-Item -ItemType Directory -Force -Path $FixtureBundle | Out-Null
  [System.IO.File]::WriteAllBytes(
    (Join-Path $FixtureBundle "mihomo-linux-arm64"),
    [byte[]](0x7f, 0x45, 0x4c, 0x46, 0x0a)
  )
  Set-Content -LiteralPath (Join-Path $FixtureBundle "ShellCrash.tar.gz") -Value "fixture" -NoNewline
  Set-Content -LiteralPath (Join-Path $FixtureBundle "MANIFEST.json") -Value '{"schema":1}' -NoNewline
  $ChecksumLines = foreach ($Name in @("mihomo-linux-arm64", "ShellCrash.tar.gz")) {
    $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $FixtureBundle $Name)).Hash.ToLowerInvariant()
    "$Hash  $Name"
  }
  Set-Content -LiteralPath (Join-Path $FixtureBundle "SHA256SUMS") -Value $ChecksumLines
  $env:DEPLOY_BUNDLE_DIR = $FixtureBundle
  $RuntimePlan = & powershell -NoProfile -ExecutionPolicy Bypass -File $Deploy -Router user@router -KnownHostsFile $KnownHosts -InstallRuntime 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0 -or $RuntimePlan -notmatch '(?m)^include_bundle=0\r?$') { throw "PowerShell runtime plan persists the bundle in JFFS" }
  if ($RuntimePlan -notmatch '(?m)^runtime_bundle_transport=temporary\r?$') { throw "PowerShell runtime plan does not disclose temporary bundle transport" }
  # Exercise native stdin under both installed PowerShell hosts. The fake SSH
  # accepts only a small argv and executes the real decoder through POSIX dash.
  $Sh = (Get-Command sh -CommandType Application -ErrorAction Stop).Source
  $Dash = Join-Path (Split-Path -Parent $Sh) '../usr/bin/dash.exe'
  if (-not (Test-Path -LiteralPath $Dash)) { $Dash = Join-Path (Split-Path -Parent $Sh) 'dash.exe' }
  $Dash = (Resolve-Path -LiteralPath $Dash).Path
  $Tools = Split-Path -Parent $Dash
  $env:DEPLOY_NATIVE_TOOLS = '/' + $Tools.Substring(0, 1).ToLowerInvariant() + $Tools.Substring(2).Replace('\', '/')
  $NativeRoot = Join-Path $FixtureRoot 'native'
  New-Item -ItemType Directory -Path $NativeRoot | Out-Null
  $env:DEPLOY_NATIVE_ROOT = '/' + $NativeRoot.Substring(0, 1).ToLowerInvariant() + $NativeRoot.Substring(2).Replace('\', '/')
  $NativeTransport = Join-Path $FixtureRoot 'native-ssh.cmd'
  [IO.File]::WriteAllText($NativeTransport, ('@"' + $Dash + '" "%~dp0native-ssh.sh" %*' + "`r`n"), [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText((Join-Path $FixtureRoot 'native-ssh.sh'), (@'
#!/bin/sh
set -eu
PATH="$DEPLOY_NATIVE_TOOLS:$PATH"
export PATH
last=''
for arg in "$@"; do
  [ "${#arg}" -le 4096 ] || exit 27
  last=$arg
done
[ "$last" = 'sh -s' ] || exit 27
count=$(cat "$DEPLOY_NATIVE_ROOT/count" 2>/dev/null || echo 0)
count=$((count + 1)); printf '%s\n' "$count" >"$DEPLOY_NATIVE_ROOT/count"
payload="$DEPLOY_NATIVE_ROOT/script.$count"
cat >"$payload"
"$DEPLOY_NATIVE_TOOLS/dash.exe" -n "$payload"
case "$(cat "$payload")" in
  *"HOME_EDGE_INSTALLATION_DIR='"*)
    target=$(sed -bn "s/^HOME_EDGE_INSTALLATION_ROUTER='\([^']*\)'$/\1/p" "$payload")
    printf 'project_install_schema=1\nproject_install_router=%s\nproject_install_state=not_installed\nproject_install_reason=no_project_artifacts\nproject_install_path=/jffs/home-edge-bootstrap\nproject_install_replace_allowed=0\n' "$target"
    exit 0 ;;
  *runtime_space_preflight_state*) echo 'runtime_space_preflight_state=ready'; exit 0 ;;
  *control_plane_rollback_state=restored*)
    [ "${DEPLOY_NATIVE_ROLLBACK_FAIL:-0}" != 1 ] || exit 29
    echo 'control_plane_rollback_state=restored'; exit 0 ;;
esac
decoder="$DEPLOY_NATIVE_ROOT/decoder.$count"
sed -bn '/^decode_payload() {/,/^}/p' "$payload" >"$decoder"
sed -bn '/^decode_payload <<.* | tar -xzf/,/^HOME_EDGE_ARCHIVE_BASE64$/p' "$payload" |
  sed -b "s# | tar -xzf - -C .*# >\"$DEPLOY_NATIVE_ROOT/archive.$count.tgz\"#" >>"$decoder"
tail -n 2 "$payload" >>"$decoder"
awk '/^decode_payload <<.* | tar -xzf/ { payload=1; next } /^HOME_EDGE_ARCHIVE_BASE64$/ { payload=0 } payload && length($0)>76 { exit 1 }' "$payload"
"$DEPLOY_NATIVE_TOOLS/dash.exe" -s <"$decoder" || exit $?
tar -tzf "$DEPLOY_NATIVE_ROOT/archive.$count.tgz" >/dev/null
[ "${DEPLOY_NATIVE_FAIL_AT:-0}" != "$count" ] || exit 23
echo 'deploy_native_archive=decoded'
exit 0
'@).Replace("`r", "") + "`n", [Text.Encoding]::ASCII)
  $FixtureRepo = Join-Path $FixtureRoot 'repo'
  foreach ($Dir in @('adapters/merlin/lib', 'config', 'docs', 'scripts', 'tools')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $FixtureRepo $Dir) | Out-Null
  }
  foreach ($Name in @('README.md', 'README.zh-CN.md', 'bootstrap.sh')) { Copy-Item -LiteralPath (Join-Path $Repo $Name) -Destination $FixtureRepo }
  foreach ($Name in @('deploy-merlin.ps1', 'check-project-installation.ps1', 'new-deployment-provenance.ps1')) { Copy-Item -LiteralPath (Join-Path $Repo "scripts/$Name") -Destination (Join-Path $FixtureRepo 'scripts') }
  Copy-Item -LiteralPath (Join-Path $Repo 'adapters/merlin/lib/installation-state.sh') -Destination (Join-Path $FixtureRepo 'adapters/merlin/lib')
  $UnicodePolicy = 'selector=' + [char]0x8282 + [char]0x70b9 + [char]0x8def + [char]0x7531 + "`n"
  [IO.File]::WriteAllText((Join-Path $FixtureRepo 'config/policy.local'), $UnicodePolicy, (New-Object Text.UTF8Encoding($false)))
  $FixtureLibrary = Join-Path $FixtureRepo 'adapters/merlin/lib/installation-state.sh'
  [IO.File]::AppendAllText($FixtureLibrary, ("`n# " + $UnicodePolicy), (New-Object Text.UTF8Encoding($false)))
  $NativeDeploy = Join-Path $FixtureRepo 'scripts/deploy-merlin.ps1'
  $NativeHosts = @((Get-Command powershell -CommandType Application).Source)
  $Pwsh = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue
  if ($Pwsh) { $NativeHosts += $Pwsh.Source }
  $env:HOME_EDGE_SSH_COMMAND = $NativeTransport
  $TarShimDir = Join-Path $FixtureRoot 'tar-bin'
  New-Item -ItemType Directory -Path $TarShimDir | Out-Null
  $NativeTar = (Get-Command tar -CommandType Application | Select-Object -First 1).Source
  $TarShim = "@echo off`r`nif `"%~2`"==`"$FixtureBundle`" goto fail_bundle`r`n@`"$NativeTar`" %*`r`nexit /b %errorlevel%`r`n:fail_bundle`r`n>`"%~dp0bundle-tar.failed`" echo 31`r`nexit /b 31`r`n"
  [IO.File]::WriteAllText((Join-Path $TarShimDir 'tar.cmd'), $TarShim, [Text.Encoding]::ASCII)
  $NativeModes = if ($LocalRuntimeArchiveOnly) { @('local_runtime_archive_failure') } else { @('ready', 'apply_failure', 'runtime_failure', 'rollback_failure', 'local_runtime_archive_failure') }
  foreach ($NativeHost in $NativeHosts) {
    foreach ($Mode in $NativeModes) {
      Remove-Item -LiteralPath (Join-Path $NativeRoot 'count') -ErrorAction SilentlyContinue
      $env:DEPLOY_NATIVE_FAIL_AT = if ($Mode -eq 'apply_failure') { '2' } elseif ($Mode -in @('runtime_failure', 'rollback_failure')) { '4' } else { '0' }
      $env:DEPLOY_NATIVE_ROLLBACK_FAIL = if ($Mode -eq 'rollback_failure') { '1' } else { '0' }
      $RunArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $NativeDeploy, '-Router', 'user@router', '-KnownHostsFile', $KnownHosts, '-Apply')
      if ($Mode -in @('runtime_failure', 'rollback_failure', 'local_runtime_archive_failure')) { $RunArgs += '-InstallRuntime' }
      if ($Mode -eq 'local_runtime_archive_failure') {
        Remove-Item -LiteralPath (Join-Path $TarShimDir 'bundle-tar.failed') -ErrorAction SilentlyContinue
        # Limit PATH injection to this child. The caller and native SSH shim
        # keep their normal tool lookup, including their extraction tar.
        $Start = New-Object Diagnostics.ProcessStartInfo
        $Start.FileName = $NativeHost
        $Start.Arguments = ($RunArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $Start.UseShellExecute = $false
        $Start.CreateNoWindow = $true
        $Start.RedirectStandardOutput = $true
        $Start.RedirectStandardError = $true
        $CallerPath = $env:PATH
        $Start.EnvironmentVariables['PATH'] = $TarShimDir + ';' + $CallerPath
        $Child = New-Object Diagnostics.Process
        $Child.StartInfo = $Start
        try {
          $null = $Child.Start()
          $Stdout = $Child.StandardOutput.ReadToEndAsync()
          $Stderr = $Child.StandardError.ReadToEndAsync()
          $Child.WaitForExit()
          $NativeStatus = $Child.ExitCode
          $NativeOutput = $Stdout.GetAwaiter().GetResult() + $Stderr.GetAwaiter().GetResult()
        } finally { $Child.Dispose() }
        if ($env:PATH -cne $CallerPath) { throw 'Local tar failure seam changed the caller PATH' }
        if (-not (Test-Path -LiteralPath (Join-Path $TarShimDir 'bundle-tar.failed')) -or $NativeOutput -notmatch 'Failed to create temporary runtime bundle archive') { throw 'Local runtime archive failure seam was not exercised' }
      } else {
        $ErrorActionPreference = 'Continue'
        $NativeOutput = & $NativeHost @RunArgs 2>&1 | Out-String
        $NativeStatus = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
      }
      $ExpectedStatus = if ($Mode -eq 'ready') { 0 } elseif ($Mode -in @('rollback_failure', 'local_runtime_archive_failure')) { 1 } else { 23 }
      $ExpectedCount = if ($Mode -in @('ready', 'apply_failure', 'local_runtime_archive_failure')) { 2 } else { 5 }
      $NativeCount = [int](Get-Content (Join-Path $NativeRoot 'count'))
      if ($NativeStatus -ne $ExpectedStatus -or $NativeCount -ne $ExpectedCount) { throw "Native deploy status/sequence failed: $NativeHost/$Mode status=$NativeStatus calls=$NativeCount expected_calls=$ExpectedCount`n$NativeOutput" }
      if ($Mode -eq 'local_runtime_archive_failure') {
        $Preflight = [IO.File]::ReadAllText((Join-Path $NativeRoot 'script.2'), [Text.Encoding]::UTF8)
        if ($Preflight -notmatch 'runtime_space_preflight_state' -or $Preflight -match 'acquire_deploy_lock') { throw 'Local bundle failure was observed after a remote transaction' }
        Write-Host "deploy_local_runtime_archive_failure=ok host=$NativeHost"
      }
      if ($Mode -eq 'ready') {
        foreach ($Number in @(1, 2)) {
          if (-not [IO.File]::ReadAllText((Join-Path $NativeRoot "script.$Number"), [Text.Encoding]::UTF8).Contains($UnicodePolicy.TrimEnd("`n"))) { throw 'Native observer/deployment stdin lost UTF8 library text' }
        }
        $Extract = Join-Path $NativeRoot 'extract'
        New-Item -ItemType Directory -Force -Path $Extract | Out-Null
        & tar -xzf (Join-Path $NativeRoot 'archive.2.tgz') -C $Extract
        if ($LASTEXITCODE -ne 0) { throw 'Native archive extraction failed' }
        foreach ($Name in @('config/policy.local', 'scripts/deploy-merlin.ps1', 'adapters/merlin/lib/installation-state.sh')) {
          if ((Get-FileHash -LiteralPath (Join-Path $Extract $Name)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $FixtureRepo $Name)).Hash) { throw "Native transported bytes changed: $Name" }
        }
        foreach ($Line in Get-Content -LiteralPath (Join-Path $Extract 'DEPLOYMENT-CONTENT-SHA256SUMS')) {
          $Parts = $Line -split '\s+', 2
          if ((Get-FileHash -LiteralPath (Join-Path $Extract $Parts[1])).Hash.ToLowerInvariant() -ne $Parts[0]) { throw 'Native archive provenance differs from received bytes' }
        }
      }
    }
    if (-not $LocalRuntimeArchiveOnly) { Write-Host "deploy_native_transport=ok host=$NativeHost" }
  }
} finally {
  $env:DEPLOY_BUNDLE_DIR = $PreviousBundleDir
  $env:HOME_EDGE_SSH_COMMAND = $PreviousSsh
  foreach ($Name in $NativeNames) { [Environment]::SetEnvironmentVariable($Name, $NativePrevious[$Name]) }
  Remove-Item -LiteralPath $FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
$Source = Get-Content -LiteralPath $Deploy -Raw
$ParseTokens = $null; $ParseErrors = $null
$DeployAst = [Management.Automation.Language.Parser]::ParseFile($Deploy, [ref]$ParseTokens, [ref]$ParseErrors)
if ($ParseErrors.Count) { throw 'Deploy source has syntax errors' }
$Transport = $DeployAst.Find({ param($Node)
  $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Invoke-RemoteScript'
}, $true)
if (-not $Transport) { throw 'Missing actual remote-script transport' }
# The native cases above detect encoding loss. Selected .ps1 hooks additionally
# verify that both normal return and an exception restore the caller's encoding.
& {
  param($NormalizerDefinition, $TransportDefinition)
  . ([scriptblock]::Create($NormalizerDefinition))
  . ([scriptblock]::Create($TransportDefinition))
  $HookRoot = Join-Path ([IO.Path]::GetTempPath()) ('home-edge-encoding-hook-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $HookRoot | Out-Null
  $OriginalEncoding = $global:OutputEncoding
  try {
    $SshArgs = @()
    foreach ($Throws in @($false, $true)) {
      $SshCommand = Join-Path $HookRoot 'ssh.ps1'
      $HookBody = @'
$null = $input | Out-String
if ($global:OutputEncoding.CodePage -ne 65001 -or $global:OutputEncoding.GetPreamble().Length -ne 0) { throw 'Selected SSH hook did not receive BOM-less UTF8 encoding' }
if ($args[-1] -ne 'sh -s') { throw 'Selected SSH hook lost the short command' }
$global:LASTEXITCODE = 23
'@
      if ($Throws) { $HookBody += "`nthrow 'fixture_transport_failure'" }
      Set-Content -LiteralPath $SshCommand -Value $HookBody -Encoding ASCII
      $Sentinel = New-Object Text.ASCIIEncoding
      $global:OutputEncoding = $Sentinel
      $Caught = $false
      try { Invoke-RemoteScript 'set -eu' } catch {
        if ($_.Exception.Message -ne 'fixture_transport_failure') { throw }
        $Caught = $true
      }
      if ($Caught -ne $Throws -or -not [object]::ReferenceEquals($Sentinel, $global:OutputEncoding)) { throw 'SSH helper did not restore caller encoding after return/exception' }
      if (-not $Throws -and $LASTEXITCODE -ne 23) { throw 'Selected SSH hook failure status was lost' }
    }
  } finally {
    $global:OutputEncoding = $OriginalEncoding
    Remove-Item -LiteralPath $HookRoot -Recurse -Force
  }
} ($DeployAst.Find({ param($Node)
  $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'ConvertTo-PosixRemoteCommand'
}, $true).Extent.Text) $Transport.Extent.Text
$Normalizer = $DeployAst.Find({ param($Node)
  $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'ConvertTo-PosixRemoteCommand'
}, $true)
if (-not $Normalizer) { throw 'Missing actual remote-command normalizer' }
& {
  param($Definition)
  . ([scriptblock]::Create($Definition))
  $Normalized = ConvertTo-PosixRemoteCommand "set -eu`r`nprintf 'ok\n'`r`n"
  if ($Normalized.Contains("`r") -or $Normalized -ne "set -eu`nprintf 'ok\n'`n") {
    throw 'Remote shell commands retain CRLF'
  }
} $Normalizer.Extent.Text
foreach ($CommandName in @('Remote', 'RuntimeSpaceRemote', 'RuntimeRemote', 'RuntimeRollbackRemote')) {
  if ($Source -notmatch ('\$' + $CommandName + '\s*=\s*ConvertTo-PosixRemoteCommand\s')) {
    throw "Remote command bypasses LF conversion: $CommandName"
  }
}
if ($Source -notmatch 'DEPLOY_BUNDLE_DIR') { throw "PowerShell deploy lacks a temporary bundle override for fixture and offline use" }
if ($Source -notmatch 'new-deployment-provenance\.ps1') { throw "PowerShell deploy does not generate provenance from staged bytes" }
if ($Source -notmatch 'DEPLOYMENT-CONTENT-SHA256SUMS') { throw "PowerShell deploy lacks provenance archive contract" }
if ($Source -notmatch '/jffs/home-edge-bootstrap-state/lifecycle/state\.env') { throw "PowerShell deploy does not verify stable state schema" }
if ($Source -notmatch 'stable_state_root=/jffs/home-edge-bootstrap-state') { throw "PowerShell deploy does not verify stable state root metadata" }
if ($Source -notmatch 'cleanup_first_install_active_state') { throw "PowerShell deploy does not clean first-install active surfaces on rollback" }
if ($Source -notmatch 'home-edge-start-shellcrash\.sh\s+\\\s+home-edge-configure-service-rules\.sh') {
  throw "PowerShell deploy cleanup list does not include the service-rules helper safely"
}
if ($Source -notmatch 'BOOTSTRAP_BUNDLE_DIR') { throw "PowerShell deploy does not bind a temporary runtime bundle directory" }
if ($Source -notmatch 'BOOTSTRAP_RUNTIME_FOLLOWS=1') { throw "PowerShell deploy does not declare its two-stage runtime continuation" }
if ($Source -notmatch 'deploy_state=staged') { throw "PowerShell deploy does not stage the control plane before runtime activation" }
if ($Source -notmatch 'control_plane_rollback_state=restored') { throw "PowerShell deploy lacks previous control-plane restoration after runtime failure" }
if ($Source -notmatch 'control_plane_rollback_state=removed') { throw "PowerShell deploy lacks first-install staged control-plane cleanup after runtime failure" }
if ($Source -notmatch 'RuntimeRollbackRemote') { throw "PowerShell deploy does not invoke a separate runtime-failure rollback" }
if ($Source -notmatch '(?s)\$RuntimeRollbackTemplate\s*=\s*@''.*cleanup_first_install_active_state') {
  throw "PowerShell runtime-failure rollback does not clean first-install active surfaces"
}
if ($Source -notmatch '(?s)\$RuntimeRollbackTemplate\s*=\s*@''.*HOME_EDGE_WRITE_LOCK_HELD=1 BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 BOOTSTRAP_INSTALL_DIR="\$remote_dir" sh "\$remote_dir/bootstrap\.sh"') {
  throw "PowerShell runtime-failure rollback does not replay the restored control plane"
}
if ($Source -notmatch '(?s)\$RuntimeTemplate\s*=\s*@''.*BOOTSTRAP_INSTALL_RUNTIME=1\s+\\\s+BOOTSTRAP_INSTALL_DIR="\$remote_dir"') {
  throw 'PowerShell runtime activation lost its custom installation target'
}
if ($Source -notmatch 'RuntimePayloadBytes \* 2') { throw "PowerShell deploy does not derive conservative space from host bundle size" }
if ($Source -notmatch 'LC_ALL=C df -k /tmp') { throw "PowerShell deploy lacks portable remote /tmp space inspection" }
if ($Source -notmatch 'runtime_space_preflight_state=ready') { throw "PowerShell deploy lacks a ready space marker" }
if ($Source -notmatch 'runtime_space_preflight_state=insufficient') { throw "PowerShell deploy lacks an insufficient space marker" }
if ($Source.IndexOf('$RuntimeSpaceRemote') -gt $Source.IndexOf('New-Item -ItemType Directory -Force $Stage')) { throw "PowerShell space preflight occurs after deployment staging" }
if ($Source -notmatch 'openssl base64 -d -A') { throw "PowerShell deploy lacks a Merlin-compatible base64 decoder fallback" }
if ($Source -notmatch "tr -cd 'A-Za-z0-9\+/='") { throw "PowerShell deploy does not normalize BOM/CRLF-contaminated base64 input" }
if ($Source -match 'command -v') { throw "PowerShell remote deploy must not depend on command -v" }
Write-Host "deploy_fixture_tests_ps=ok"
