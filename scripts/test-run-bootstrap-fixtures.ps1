param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$Script = Join-Path $Repo "scripts\run-bootstrap.ps1"
$Base = Join-Path ([System.IO.Path]::GetTempPath()) ("home-edge-run-bootstrap-fixtures-ps-" + $PID)
Remove-Item -LiteralPath $Base -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Base | Out-Null

function Invoke-BootstrapFixture {
  param(
    [string]$Name,
    [string]$GuideJson,
    [string]$CloseoutOutput = "",
    [string]$ExpectedState,
    [string]$ExpectedAction = "",
    [string[]]$ForbiddenLogs = @()
  )
  $Session = Join-Path $Base $Name
  $env:BOOTSTRAP_FIXTURE_GUIDE_JSON = $GuideJson
  $env:BOOTSTRAP_TEST_MODE = "1"
  if ($CloseoutOutput) { $env:BOOTSTRAP_FIXTURE_CLOSEOUT_OUTPUT = $CloseoutOutput }
  try {
    $Output = powershell -NoProfile -ExecutionPolicy Bypass -File $Script -Router "user@192.168.50.1" -SessionDir $Session -NoPause -AcceptClientRuntime -ClientConfirmed | Out-String
  }
  finally {
    Remove-Item Env:\BOOTSTRAP_FIXTURE_GUIDE_JSON -ErrorAction SilentlyContinue
    Remove-Item Env:\BOOTSTRAP_FIXTURE_CLOSEOUT_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item Env:\BOOTSTRAP_TEST_MODE -ErrorAction SilentlyContinue
  }
  if ($Output -notmatch "bootstrap_state=$ExpectedState") {
    throw "$Name expected bootstrap_state=$ExpectedState got: $Output"
  }
  if ($ExpectedAction -and $Output -notmatch "next_action_code=$ExpectedAction") {
    throw "$Name expected next_action_code=$ExpectedAction got: $Output"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $Session "logs\bootstrap.log"))) {
    throw "$Name missing bootstrap log"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $Session "state.json"))) {
    throw "$Name missing state.json"
  }
  foreach ($ForbiddenLog in $ForbiddenLogs) {
    if (Test-Path -LiteralPath (Join-Path $Session (Join-Path "logs" $ForbiddenLog))) {
      throw "$Name created forbidden log: $ForbiddenLog"
    }
  }
  $StatePath = Join-Path $Session "state.json"
  $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
  $ExpectedKnownHosts = Join-Path $Session "known_hosts"
  if ($State.known_hosts_file -ne $ExpectedKnownHosts) {
    throw "$Name state does not retain the session known_hosts path"
  }
  if (Test-Path -LiteralPath "$StatePath.tmp") {
    throw "$Name left an atomic state temp file"
  }
  if (Test-Path -LiteralPath (Join-Path $Session ".bootstrap.lock")) {
    throw "$Name left a bootstrap lock"
  }
  if (($ExpectedState -eq "pass" -or $ExpectedState -eq "accepted_boundary") -and (Test-Path -LiteralPath (Join-Path $Session "scratch"))) {
    throw "$Name did not clean scratch after terminal result"
  }
}

Invoke-BootstrapFixture -Name waiting_prereqs -ExpectedState waiting_manual -ExpectedAction enable_router_prereqs -GuideJson '{"guide_state":"ready","next_action_code":"enable_router_prereqs","next_action_command":"guide"}'
Invoke-BootstrapFixture -Name deploy_requires_apply -ExpectedState waiting_manual -ExpectedAction deploy_plan -ForbiddenLogs @("deploy-plan.log", "deploy-apply.log") -GuideJson '{"guide_state":"ready","next_action_code":"deploy_plan","next_action_command":"deploy"}'
Invoke-BootstrapFixture -Name repair_registration -ExpectedState waiting_manual -ExpectedAction repair_self_heal_registration -GuideJson '{"guide_state":"ready","next_action_code":"repair_self_heal_registration","next_action_command":"repair"}'

Invoke-BootstrapFixture -Name pass_closeout -ExpectedState pass -GuideJson '{"guide_state":"ready","next_action_code":"monitor_live_managed","next_action_command":"status"}' -CloseoutOutput @"
repository_gate=pass
router_gate=pass
runtime_gate=pass
route_gate=pass
subscription_gate=pass
client_gate=pass
installation_closeout_state=pass
next_action=none
"@

Invoke-BootstrapFixture -Name accepted_boundary_closeout -ExpectedState accepted_boundary -GuideJson '{"guide_state":"ready","next_action_code":"monitor_live_managed","next_action_command":"status"}' -CloseoutOutput @"
repository_gate=pass
router_gate=pass
runtime_gate=pass
route_gate=pass
subscription_gate=accepted_manual_boundary
dashboard_gate=not_applicable
client_gate=pass
installation_closeout_state=accepted_boundary
next_action=none
"@

$BusySession = Join-Path $Base "busy_lock"
$BusyLock = Join-Path $BusySession ".bootstrap.lock"
New-Item -ItemType Directory -Force $BusyLock | Out-Null
$CurrentProcess = Get-Process -Id $PID
[ordered]@{
  pid = $PID
  process_start_utc = $CurrentProcess.StartTime.ToUniversalTime().ToString("o")
  started_at = (Get-Date).ToString("o")
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $BusyLock "owner.json") -Encoding UTF8
$env:BOOTSTRAP_TEST_MODE = "1"
$env:BOOTSTRAP_FIXTURE_GUIDE_JSON = '{"guide_state":"ready","next_action_code":"enable_router_prereqs","next_action_command":"guide"}'
try {
  $BusyOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $Script -Router "user@192.168.50.1" -SessionDir $BusySession -NoPause 2>&1 | Out-String
  $BusyExit = $LASTEXITCODE
}
finally {
  Remove-Item Env:\BOOTSTRAP_TEST_MODE -ErrorAction SilentlyContinue
  Remove-Item Env:\BOOTSTRAP_FIXTURE_GUIDE_JSON -ErrorAction SilentlyContinue
}
if ($BusyExit -ne 75) {
  throw "active bootstrap lock should exit 75, got $BusyExit"
}
if ($BusyOutput -notmatch "bootstrap_state=busy") {
  throw "active bootstrap lock did not report busy"
}
Remove-Item -LiteralPath $BusySession -Recurse -Force

$UnownedSession = Join-Path $Base "unowned_scratch"
$UnownedScratch = Join-Path $UnownedSession "scratch"
New-Item -ItemType Directory -Force $UnownedScratch | Out-Null
$UnownedFile = Join-Path $UnownedScratch "user-file"
Set-Content -LiteralPath $UnownedFile -Value "preserve" -Encoding ASCII
$env:BOOTSTRAP_TEST_MODE = "1"
$env:BOOTSTRAP_FIXTURE_GUIDE_JSON = '{"guide_state":"ready","next_action_code":"enable_router_prereqs","next_action_command":"guide"}'
$PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
  $UnownedOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $Script -Router "user@192.168.50.1" -SessionDir $UnownedSession -NoPause 2>&1 | Out-String
  $UnownedExit = $LASTEXITCODE
}
finally {
  Remove-Item Env:\BOOTSTRAP_TEST_MODE -ErrorAction SilentlyContinue
  Remove-Item Env:\BOOTSTRAP_FIXTURE_GUIDE_JSON -ErrorAction SilentlyContinue
  $ErrorActionPreference = $PreviousErrorActionPreference
}
if ($UnownedExit -eq 0) {
  throw "unowned scratch directory should be rejected"
}
if ($UnownedOutput -notmatch "unowned scratch") {
  throw "unowned scratch rejection message missing"
}
if (-not (Test-Path -LiteralPath $UnownedFile -PathType Leaf)) {
  throw "unowned scratch content was removed"
}

$RootSession = [IO.Path]::GetPathRoot($Base)
$ErrorActionPreference = "Continue"
$RootOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $Script -Router "user@192.168.50.1" -SessionDir $RootSession -NoPause 2>&1 | Out-String
$RootExit = $LASTEXITCODE
$ErrorActionPreference = $PreviousErrorActionPreference
if ($RootExit -eq 0) {
  throw "filesystem-root session directory should be rejected"
}
if ($RootOutput -notmatch "Unsafe bootstrap session directory") {
  throw "unsafe root session message missing"
}

$StaleSession = Join-Path $Base "stale_lock"
$StaleLock = Join-Path $StaleSession ".bootstrap.lock"
New-Item -ItemType Directory -Force $StaleLock | Out-Null
[ordered]@{
  pid = 999999
  process_start_utc = "2000-01-01T00:00:00.0000000Z"
  started_at = "2000-01-01T00:00:00Z"
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $StaleLock "owner.json") -Encoding UTF8
$env:BOOTSTRAP_TEST_MODE = "1"
$env:BOOTSTRAP_FIXTURE_GUIDE_JSON = '{"guide_state":"ready","next_action_code":"enable_router_prereqs","next_action_command":"guide"}'
try {
  $StaleOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $Script -Router "user@192.168.50.1" -SessionDir $StaleSession -NoPause 2>&1 | Out-String
  $StaleExit = $LASTEXITCODE
}
finally {
  Remove-Item Env:\BOOTSTRAP_TEST_MODE -ErrorAction SilentlyContinue
  Remove-Item Env:\BOOTSTRAP_FIXTURE_GUIDE_JSON -ErrorAction SilentlyContinue
}
if ($StaleExit -ne 0 -or $StaleOutput -notmatch "bootstrap_state=waiting_manual") {
  throw "stale bootstrap lock was not recovered"
}
if (Test-Path -LiteralPath $StaleLock) {
  throw "recovered stale bootstrap lock was not released"
}

Remove-Item -LiteralPath $Base -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "run_bootstrap_fixture_tests=ok"
