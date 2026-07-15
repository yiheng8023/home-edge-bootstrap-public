param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$Base = Join-Path ([System.IO.Path]::GetTempPath()) ("home-edge-router-status-test-ps-" + $PID)
$FakeBin = Join-Path $Base "bin"
$LogPath = Join-Path $Base "status.log"
$KnownHosts = Join-Path $Base "known_hosts"
$PowerShellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$GitExe = (Get-Command git.exe -ErrorAction Stop).Source
New-Item -ItemType Directory -Force $FakeBin | Out-Null
Set-Content -LiteralPath (Join-Path $FakeBin "ssh.cmd") -Encoding ASCII -Value @(
  "@echo off",
  '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "[IO.File]::WriteAllText($env:ROUTER_STATUS_FAKE_SCRIPT,[Console]::In.ReadToEnd(),(New-Object Text.UTF8Encoding($false)))"',
  "exit /b 42"
)

function Invoke-StatusHelper {
  param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$PathValue,
    [Parameter(Mandatory = $true)][string]$CapturePath
  )

  $env:PATH = $PathValue
  $env:ROUTER_STATUS_FAKE_SCRIPT = $CapturePath
  $PreviousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $Output = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SourceRoot "scripts\check-router-status.ps1") -Router "user@router" -LogPath $LogPath -KnownHostsFile $KnownHosts -SshCommand (Join-Path $FakeBin "ssh.cmd") -NoPause -NoLog 2>&1 | Out-String
    $Status = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $PreviousPreference
  }
  [pscustomobject]@{ Output = $Output; Status = $Status }
}

function Read-CapturedRemoteScript {
  param([Parameter(Mandatory = $true)][string]$CapturePath)
  $Payload = (Get-Content -LiteralPath $CapturePath -Raw).Trim()
  try {
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload))
  }
  catch {
    $Prefix = $Payload.Substring(0, [Math]::Min(120, $Payload.Length))
    throw "captured SSH payload is not base64 (length=$($Payload.Length), prefix=$Prefix)"
  }
}

$OldPath = $env:PATH
$OldCapturePath = $env:ROUTER_STATUS_FAKE_SCRIPT
try {
  $GitRoot = Join-Path $Base "clean-git-source"
  New-Item -ItemType Directory -Force (Join-Path $GitRoot "scripts") | Out-Null
  Copy-Item -LiteralPath (Join-Path $Repo "scripts\check-router-status.ps1") -Destination (Join-Path $GitRoot "scripts\check-router-status.ps1")
  Set-Content -LiteralPath (Join-Path $GitRoot "tracked.txt") -Encoding ASCII -Value "clean"
  & $GitExe -C $GitRoot init --quiet
  & $GitExe -C $GitRoot config user.name "Fixture User"
  & $GitExe -C $GitRoot config user.email "fixture@example.invalid"
  & $GitExe -C $GitRoot config core.autocrlf false
  & $GitExe -C $GitRoot add scripts/check-router-status.ps1 tracked.txt
  & $GitExe -C $GitRoot commit --quiet -m "fixture"

  $GitCapture = Join-Path $Base "git-source.remote.sh"
  $Result = Invoke-StatusHelper -SourceRoot $GitRoot -PathValue "$FakeBin;$OldPath" -CapturePath $GitCapture
  if ($Result.Status -ne 42) {
    throw "PowerShell status helper should propagate SSH exit 42, got $($Result.Status). Output: $($Result.Output)"
  }
  if (Test-Path -LiteralPath $LogPath) {
    throw "NoLog PowerShell status helper wrote a log"
  }
  $ExpectedCommit = (& $GitExe -C $GitRoot rev-parse HEAD).Trim()
  $GitRemote = Read-CapturedRemoteScript -CapturePath $GitCapture
  if ($GitRemote -notmatch "HOME_EDGE_EXPECTED_SOURCE_KIND=git") {
    throw "clean Git checkout did not retain Git source identity. Captured: $GitRemote"
  }
  if ($GitRemote -notmatch "HOME_EDGE_EXPECTED_SOURCE_COMMIT=$ExpectedCommit") {
    throw "clean Git checkout did not retain its exact source commit"
  }

  Set-Content -LiteralPath (Join-Path $GitRoot "tracked.txt") -Encoding ASCII -Value "dirty"
  $DirtyGitCapture = Join-Path $Base "dirty-git-source.remote.sh"
  $Result = Invoke-StatusHelper -SourceRoot $GitRoot -PathValue "$FakeBin;$OldPath" -CapturePath $DirtyGitCapture
  if ($Result.Status -ne 42) {
    throw "PowerShell status helper should reach SSH from a dirty Git checkout and propagate exit 42, got $($Result.Status). Output: $($Result.Output)"
  }
  if ((Read-CapturedRemoteScript -CapturePath $DirtyGitCapture) -notmatch "HOME_EDGE_EXPECTED_SOURCE_KIND=unknown") {
    throw "dirty Git checkout did not safely degrade to unknown identity"
  }
  & $GitExe -C $GitRoot checkout --quiet -- tracked.txt

  $NoDotGitRoot = Join-Path $Base "source-without-dot-git"
  New-Item -ItemType Directory -Force (Join-Path $NoDotGitRoot "scripts") | Out-Null
  Copy-Item -LiteralPath (Join-Path $Repo "scripts\check-router-status.ps1") -Destination (Join-Path $NoDotGitRoot "scripts\check-router-status.ps1")
  $NoDotGitCapture = Join-Path $Base "no-dot-git.remote.sh"
  $Result = Invoke-StatusHelper -SourceRoot $NoDotGitRoot -PathValue "$FakeBin;$OldPath" -CapturePath $NoDotGitCapture
  if ($Result.Status -ne 42) {
    throw "PowerShell status helper should reach SSH without a .git directory and propagate exit 42, got $($Result.Status). Output: $($Result.Output)"
  }
  if ((Read-CapturedRemoteScript -CapturePath $NoDotGitCapture) -notmatch "HOME_EDGE_EXPECTED_SOURCE_KIND=unknown") {
    throw "source tree without .git did not safely degrade to unknown identity"
  }

  $NoGitExeCapture = Join-Path $Base "no-git-executable.remote.sh"
  $Result = Invoke-StatusHelper -SourceRoot $GitRoot -PathValue $FakeBin -CapturePath $NoGitExeCapture
  if ($Result.Status -ne 42) {
    throw "PowerShell status helper should reach SSH without git.exe and propagate exit 42, got $($Result.Status). Output: $($Result.Output)"
  }
  if ((Read-CapturedRemoteScript -CapturePath $NoGitExeCapture) -notmatch "HOME_EDGE_EXPECTED_SOURCE_KIND=unknown") {
    throw "source tree without git.exe did not safely degrade to unknown identity"
  }

  $Source = Get-Content -LiteralPath (Join-Path $Repo "scripts\check-router-status.ps1") -Raw
  if ($Source -notmatch "<configured>") {
    throw "PowerShell status helper lacks sensitive-value masking"
  }
  if ($Source -match "/tmp/home-edge-check-router-status.sh") {
    throw "PowerShell status helper still uses a fixed remote temp script"
  }
  if ($Source -notmatch "verify-deployment-provenance\.sh") {
    throw "PowerShell status helper does not run the read-only provenance verifier"
  }
  if ($Source -notmatch "HOME_EDGE_EXPECTED_SOURCE_") {
    throw "PowerShell status helper does not bind expected local source identity"
  }
  foreach ($EvidenceText in @("runtime_active_config_path", "runtime_process_identity", "SUBSCRIPTION_RUNTIME_EVIDENCE_MAX_AGE_SEC", "route_evidence_probe_id", "cache_apply_path_alias", "controller_dashboard_config_state:-unknown")) {
    if ($Source -notmatch [regex]::Escape($EvidenceText)) { throw "PowerShell status helper lacks conservative evidence text: $EvidenceText" }
  }
  foreach ($Field in @("deployment_provenance_state", "deployment_source_commit", "deployment_content_id")) {
    if ($Source -notmatch $Field) { throw "PowerShell status helper lacks safe provenance field: $Field" }
  }
}
finally {
  $env:PATH = $OldPath
  $env:ROUTER_STATUS_FAKE_SCRIPT = $OldCapturePath
  Remove-Item -LiteralPath $Base -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "router_status_fixture_tests=ok"
