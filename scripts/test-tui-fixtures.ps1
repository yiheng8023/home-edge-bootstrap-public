param([string]$Repo = "")

$ErrorActionPreference = "Stop"
if (-not $Repo) { $Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }

$Base = Join-Path ([IO.Path]::GetTempPath()) ("home-edge-tui-test-ps-" + $PID)
if (Test-Path -LiteralPath $Base) { Remove-Item -LiteralPath $Base -Recurse -Force }
New-Item -ItemType Directory -Path $Base | Out-Null

function Fail([string]$Message) {
  Write-Error "tui_fixture_tests=failed`n$Message"
  exit 1
}

function Read-CallLog([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return "" }
  return [string](Get-Content -LiteralPath $Path -Raw)
}

function Invoke-TuiProcess {
  param(
    [string]$Script,
    [string[]]$Arguments = @(),
    [string]$InputText = "",
    [hashtable]$Environment = @{}
  )
  $StartInfo = [Diagnostics.ProcessStartInfo]::new()
  $StartInfo.FileName = "powershell"
  $QuotedScript = '"' + $Script.Replace('"', '\"') + '"'
  $StartInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File $QuotedScript " + ($Arguments -join " ")
  $StartInfo.RedirectStandardInput = $true
  $StartInfo.RedirectStandardOutput = $true
  $StartInfo.RedirectStandardError = $true
  $StartInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
  $StartInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
  $StartInfo.UseShellExecute = $false
  foreach ($Key in $Environment.Keys) { $StartInfo.EnvironmentVariables[$Key] = [string]$Environment[$Key] }
  $Process = [Diagnostics.Process]::Start($StartInfo)
  if ($InputText) { $Process.StandardInput.Write($InputText) }
  $Process.StandardInput.Close()
  $Output = $Process.StandardOutput.ReadToEnd()
  $ErrorOutput = $Process.StandardError.ReadToEnd()
  $Process.WaitForExit()
  [pscustomobject]@{ Status = $Process.ExitCode; Output = $Output; Error = $ErrorOutput }
}

try {
  $Tui = Join-Path $Repo "scripts\tui.ps1"
  if (-not (Test-Path -LiteralPath $Tui -PathType Leaf)) { Fail "missing PowerShell TUI entrypoint" }

  $FakeRepo = Join-Path $Base "repo"
  $FakeScripts = Join-Path $FakeRepo "scripts"
  New-Item -ItemType Directory -Path $FakeScripts -Force | Out-Null
  $FakeTui = Join-Path $FakeScripts "tui.ps1"
  Copy-Item -LiteralPath $Tui -Destination $FakeTui
  @'
param([switch]$Json, [string]$Router = "")
$Parts = @()
if ($Json) { $Parts += "-Json" }
if ($Router) { $Parts += $Router }
Add-Content -LiteralPath $env:TUI_FIXTURE_CALL_LOG -Value ("doctor " + ($Parts -join " "))
Write-Host '{"doctor_state":"ready","next_action_code":"monitor_live_managed"}'
if ($env:DOCTOR_STUB_EXIT) { exit [int]$env:DOCTOR_STUB_EXIT }
'@ | Set-Content -LiteralPath (Join-Path $FakeScripts "doctor.ps1") -Encoding ASCII
  @'
param(
  [string]$Router = "",
  [string]$SessionDir = "",
  [switch]$NoPause,
  [switch]$ApplyDeploy,
  [switch]$EnableLiveSelfHeal
)
$Parts = @()
if ($NoPause) { $Parts += "-NoPause" }
if ($ApplyDeploy) { $Parts += "-ApplyDeploy" }
if ($EnableLiveSelfHeal) { $Parts += "-EnableLiveSelfHeal" }
if ($SessionDir) { $Parts += @("-SessionDir", $SessionDir) }
if ($Router) { $Parts += $Router }
Add-Content -LiteralPath $env:TUI_FIXTURE_CALL_LOG -Value ("run-bootstrap " + ($Parts -join " "))
if ($env:BOOTSTRAP_STUB_MALFORMED -eq "1") {
  Write-Host 'not-machine-readable-state'
  exit 0
}
Write-Host 'bootstrap_state=waiting_manual'
Write-Host ("next_action_code=" + $(if ($env:BOOTSTRAP_STUB_ACTION) { $env:BOOTSTRAP_STUB_ACTION } else { "monitor_live_managed" }))
Write-Host 'next_action_command=resume-command'
Write-Host 'session_dir=C:\fixture\session'
Write-Host 'log_path=C:\fixture\bootstrap.log'
if (($ApplyDeploy -or $EnableLiveSelfHeal) -and $env:BOOTSTRAP_STUB_WRITE_EXIT) { exit [int]$env:BOOTSTRAP_STUB_WRITE_EXIT }
if ($env:BOOTSTRAP_STUB_EXIT) { exit [int]$env:BOOTSTRAP_STUB_EXIT }
'@ | Set-Content -LiteralPath (Join-Path $FakeScripts "run-bootstrap.ps1") -Encoding ASCII
  @'
Add-Content -LiteralPath $env:TUI_FIXTURE_CALL_LOG -Value 'check-no-wall'
Write-Host 'bundle_state=verified'
'@ | Set-Content -LiteralPath (Join-Path $FakeScripts "check-no-wall-readiness.ps1") -Encoding ASCII
  @'
param([string]$Router = "")
Add-Content -LiteralPath $env:TUI_FIXTURE_CALL_LOG -Value ("support-bundle " + $Router)
Write-Host 'support_bundle_state=ready'
'@ | Set-Content -LiteralPath (Join-Path $FakeScripts "export-support-bundle.ps1") -Encoding ASCII
  @'
param([string]$Router = "", [switch]$Apply, [string]$Confirmation = "", [switch]$NoPause)
$Parts = @()
if ($NoPause) { $Parts += "-NoPause" }
if ($Apply) { $Parts += "-Apply" }
if ($Confirmation) { $Parts += @("-Confirmation", $Confirmation) }
if ($Router) { $Parts += @("-Router", $Router) }
Add-Content -LiteralPath $env:TUI_FIXTURE_CALL_LOG -Value ("decommission-merlin " + ($Parts -join " "))
Write-Host 'decommission_state=plan_ready'
'@ | Set-Content -LiteralPath (Join-Path $FakeScripts "decommission-merlin.ps1") -Encoding ASCII

  $SupportStub = Join-Path $FakeScripts "export-support-bundle.ps1"
  $SupportMissing = "$SupportStub.missing"
  Move-Item -LiteralPath $SupportStub -Destination $SupportMissing
  if ((Invoke-TuiProcess -Script $FakeTui -Arguments @("-Help")).Status -ne 0) { Fail "help should bypass startup prerequisites" }
  if ((Invoke-TuiProcess -Script $FakeTui -Arguments @("-Version")).Status -ne 0) { Fail "version should bypass startup prerequisites" }
  $StartupMissing = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "0`n"
  if ($StartupMissing.Status -ne 2 -or $StartupMissing.Output -notmatch "startup_state=failed") { Fail "missing startup prerequisite was not rejected" }
  Move-Item -LiteralPath $SupportMissing -Destination $SupportStub

  $Default = Invoke-TuiProcess -Script $FakeTui -Arguments @("-NoColor") -InputText "0`n"
  $English = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "0`n"
  $Help = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Help")
  $Version = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Version")
  $Invalid = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "invalid")

  $ExpectedChinese = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("MS4g5byA5aeL5oiW5o6l57ut5byV5a+85byP6YWN572u"))
  $ExpectedChineseDecommission = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("Ny4g5a6h5p+l6aG555uu6YCA5Ye6"))
  if ($Default.Status -ne 0 -or $Default.Output -notmatch [regex]::Escape($ExpectedChinese)) { Fail "default menu is not Chinese" }
  if ($English.Status -ne 0 -or $English.Output -notmatch [regex]::Escape("1. Start or resume guided bootstrap")) { Fail "English menu missing" }
  if ($Default.Output -notmatch [regex]::Escape($ExpectedChineseDecommission)) { Fail "Chinese decommission menu missing" }
  if ($English.Output -notmatch [regex]::Escape("7. Review project decommission")) { Fail "English decommission menu missing" }
  foreach ($Number in @(1, 2, 3, 4, 5, 6, 7, 0)) {
    if ($Default.Output -notmatch "(?m)^$Number\. ") { Fail "default menu missing action $Number" }
    if ($English.Output -notmatch "(?m)^$Number\. ") { Fail "English menu missing action $Number" }
  }
  if ($Help.Status -ne 0 -or $Help.Output -notmatch "usage:") { Fail "help output missing usage" }
  if ($Version.Status -ne 0 -or $Version.Output.Trim() -ne "home-edge-bootstrap development") { Fail "development version output mismatch" }
  if ($Invalid.Status -ne 2) { Fail "invalid language should exit 2" }
  $RouterInjection = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", 'user@router;Write-Host-INJECTED')
  if ($RouterInjection.Status -ne 2) { Fail "unsafe router target should exit 2" }
  if ($Default.Output.Contains([char]27) -or $English.Output.Contains([char]27)) { Fail "no-color output contains ANSI escapes" }

  $CallLog = Join-Path $Base "calls.log"
  $CommonEnvironment = @{ TUI_FIXTURE_CALL_LOG = $CallLog }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $Doctor = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "2`n0`n" -Environment $CommonEnvironment
  $DoctorCalls = ([string](Read-CallLog $CallLog)).Trim()
  if ($DoctorCalls -ne "doctor -Json") { Fail "diagnosis did not dispatch doctor -Json; actual=[$DoctorCalls] output=[$($Doctor.Output)] error=[$($Doctor.Error)]" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $Bundle = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "4`n0`n" -Environment $CommonEnvironment
  if (([string](Read-CallLog $CallLog)).Trim() -ne "check-no-wall") { Fail "bundle verification dispatch mismatch" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $Support = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "5`n0`n" -Environment $CommonEnvironment
  if (([string](Read-CallLog $CallLog)).Trim() -ne "support-bundle") { Fail "support bundle dispatch mismatch" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $DecommissionCancel = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "7`nWRONG`n0`n" -Environment $CommonEnvironment
  $DecommissionCancelCalls = Get-Content -LiteralPath $CallLog
  if ($DecommissionCancelCalls -notcontains "decommission-merlin -NoPause -Router user@192.168.50.1") { Fail "PowerShell TUI omitted read-only decommission plan" }
  if ($DecommissionCancelCalls -match "-Apply") { Fail "PowerShell wrong token enabled decommission" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $DecommissionApply = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "7`nDECOMMISSION`n0`n" -Environment $CommonEnvironment
  $DecommissionApplyCalls = Get-Content -LiteralPath $CallLog
  if ($DecommissionApplyCalls -notcontains "decommission-merlin -NoPause -Router user@192.168.50.1") { Fail "PowerShell TUI omitted decommission plan before apply" }
  if ($DecommissionApplyCalls -notcontains "decommission-merlin -NoPause -Apply -Confirmation DECOMMISSION -Router user@192.168.50.1") { Fail "PowerShell exact token did not enable decommission" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $DecommissionEof = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "7`n" -Environment $CommonEnvironment
  $DecommissionEofCalls = Get-Content -LiteralPath $CallLog
  if ($DecommissionEofCalls -notcontains "decommission-merlin -NoPause -Router user@192.168.50.1") { Fail "PowerShell decommission EOF omitted read-only plan" }
  if ($DecommissionEofCalls -match "-Apply") { Fail "PowerShell EOF enabled decommission" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $InvalidChoice = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "9`n0`n" -Environment $CommonEnvironment
  if (([string](Read-CallLog $CallLog)).Length -ne 0) { Fail "invalid choice dispatched a child" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $ApplyCancel = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "1`nWRONG`n0`n" -Environment (@{ TUI_FIXTURE_CALL_LOG = $CallLog; BOOTSTRAP_STUB_ACTION = "deploy_plan" })
  $ApplyCancelCalls = Get-Content -LiteralPath $CallLog
  if ($ApplyCancelCalls -notcontains "run-bootstrap -NoPause user@192.168.50.1") { Fail "bootstrap read-only pass missing" }
  if ($ApplyCancelCalls -match "ApplyDeploy") { Fail "wrong token enabled deploy" }

  foreach ($WrongToken in @("apply", "APPLY ", "yes")) {
    Set-Content -LiteralPath $CallLog -Value "" -NoNewline
    [void](Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "1`n$WrongToken`n0`n" -Environment (@{ TUI_FIXTURE_CALL_LOG = $CallLog; BOOTSTRAP_STUB_ACTION = "deploy_plan" }))
    if ((Read-CallLog $CallLog) -match "ApplyDeploy") { Fail "non-exact token enabled deploy: $WrongToken" }
  }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $Apply = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "1`nAPPLY`n0`n" -Environment (@{ TUI_FIXTURE_CALL_LOG = $CallLog; BOOTSTRAP_STUB_ACTION = "deploy_plan" })
  if ((Get-Content -LiteralPath $CallLog) -notcontains "run-bootstrap -NoPause -ApplyDeploy user@192.168.50.1") { Fail "APPLY token did not enable deploy" }
  foreach ($Expected in @("expected_effect=apply_reviewed_deployment_plan", "rollback_path=powershell -File scripts\rollback-merlin.ps1", "session_destination=C:\fixture\session", "log_destination=C:\fixture\bootstrap.log")) {
    if ($Apply.Output -notmatch [regex]::Escape($Expected)) { Fail "deploy disclosure missing: $Expected" }
  }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $Enable = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "1`nENABLE`n0`n" -Environment (@{ TUI_FIXTURE_CALL_LOG = $CallLog; BOOTSTRAP_STUB_ACTION = "enable_live_self_heal" })
  if ((Get-Content -LiteralPath $CallLog) -notcontains "run-bootstrap -NoPause -EnableLiveSelfHeal user@192.168.50.1") { Fail "ENABLE token did not enable live self-heal" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $ChildError = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "1`n0`n" -Environment (@{ TUI_FIXTURE_CALL_LOG = $CallLog; BOOTSTRAP_STUB_EXIT = "17" })
  if ($ChildError.Output -notmatch "child_exit_code=17") { Fail "child exit code was not preserved" }
  if ($ChildError.Status -ne 17) { Fail "TUI process did not exit with the last child failure" }
  if ($ChildError.Output -notmatch "failed_action=bootstrap_read_only") { Fail "failed action was not reported" }
  if ($ChildError.Output -notmatch "safe_resume_command=powershell -File scripts\\run-bootstrap.ps1") { Fail "safe resume command was not reported" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $WriteError = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "1`nAPPLY`n0`n" -Environment (@{ TUI_FIXTURE_CALL_LOG = $CallLog; BOOTSTRAP_STUB_ACTION = "deploy_plan"; BOOTSTRAP_STUB_WRITE_EXIT = "19" })
  if ($WriteError.Status -ne 19 -or $WriteError.Output -notmatch "failed_action=apply_deploy" -or $WriteError.Output -notmatch "write_action_started=true") { Fail "write failure contract was not preserved" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $UnknownChild = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "1`n0`n" -Environment (@{ TUI_FIXTURE_CALL_LOG = $CallLog; BOOTSTRAP_STUB_ACTION = "unexpected_action" })
  if ($UnknownChild.Output -notmatch "attention_state=unknown_next_action") { Fail "unknown child state was not conservative" }
  if ((Read-CallLog $CallLog) -match "ApplyDeploy|EnableLiveSelfHeal") { Fail "unknown child state unlocked a write action" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $MalformedChild = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "1`n0`n" -Environment (@{ TUI_FIXTURE_CALL_LOG = $CallLog; BOOTSTRAP_STUB_MALFORMED = "1" })
  if ($MalformedChild.Output -notmatch "attention_state=malformed_child_state") { Fail "malformed child state was not conservative" }

  $SessionRoot = Join-Path $FakeRepo "logs\bootstrap"
  $SessionEnv = Join-Path $SessionRoot "01-env"
  $SessionJson = Join-Path $SessionRoot "02-json"
  $SessionUnknown = Join-Path $SessionRoot "03-unknown"
  $SessionBad = Join-Path $SessionRoot "04-bad"
  $SessionUnsafe = Join-Path $SessionRoot "05-bad;name"
  New-Item -ItemType Directory -Path $SessionEnv, $SessionJson, $SessionUnknown, $SessionBad, $SessionUnsafe -Force | Out-Null
  $MaliciousMarker = Join-Path $Base "state-was-executed"
  @("bootstrap_state=waiting_manual", "router=env-user@192.168.50.2", "next_action_code=deploy_plan", "next_action_command=env-resume-command", "session_dir=C:\fixture\env-session", "log_path=C:\fixture\env.log", ('updated_at=$(New-Item -ItemType File -Path "' + $MaliciousMarker + '")')) | Set-Content -LiteralPath (Join-Path $SessionEnv "state.env") -Encoding ASCII
  [ordered]@{ bootstrap_state = "waiting_manual"; router = "json-user@192.168.50.3"; next_action_code = "monitor_live_managed"; next_action_command = "json-resume-command"; session_dir = "C:\fixture\json-session"; log_path = "C:\fixture\json.log" } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $SessionJson "state.json") -Encoding UTF8
  @("bootstrap_state=waiting_manual", "router=unknown-user@192.168.50.4", "next_action_code=future_action", "next_action_command=future-command") | Set-Content -LiteralPath (Join-Path $SessionUnknown "state.env") -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $SessionBad "state.json") -Value "{not-json" -Encoding ASCII
  @("bootstrap_state=waiting_manual", "router=unsafe-session@192.168.50.5", "next_action_code=deploy_plan") | Set-Content -LiteralPath (Join-Path $SessionUnsafe "state.env") -Encoding ASCII

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $SessionView = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "3`n1`n0`n" -Environment $CommonEnvironment
  if ($SessionView.Output -notmatch "existing_session=1" -or $SessionView.Output -notmatch "router=env-user@192.168.50.2" -or $SessionView.Output -notmatch [regex]::Escape("log_path=C:\fixture\env.log")) { Fail "state.env session was not discovered and displayed" }
  if (Test-Path -LiteralPath $MaliciousMarker) { Fail "state.env content was executed" }
  if (([string](Read-CallLog $CallLog)).Length -ne 0) { Fail "session display dispatched a child" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $JsonView = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "3`n2`n0`n" -Environment $CommonEnvironment
  if ($JsonView.Output -notmatch "router=json-user@192.168.50.3" -or $JsonView.Output -notmatch "next_action_command=json-resume-command") { Fail "state.json session was not read" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $SelectedResume = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "1`n2`nWRONG`n0`n" -Environment (@{ TUI_FIXTURE_CALL_LOG = $CallLog; BOOTSTRAP_STUB_ACTION = "deploy_plan" })
  $SelectedCalls = Read-CallLog $CallLog
  if ($SelectedCalls -notmatch "run-bootstrap -NoPause -SessionDir .*02-json json-user@192.168.50.3") { Fail "selected session did not infer router and preserve session directory" }
  if ($SelectedResume.Output -notmatch [regex]::Escape("exact_command=powershell -File scripts\run-bootstrap.ps1 -NoPause -ApplyDeploy -SessionDir 'logs/bootstrap/02-json' -Router json-user@192.168.50.3")) { Fail "copyable selected-session command was not safely repository-relative" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $UnknownSession = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "3`n3`n0`n" -Environment $CommonEnvironment
  if ($UnknownSession.Output -notmatch "attention_state=unknown_session_state") { Fail "unknown session state was not conservative" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $BadSession = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "3`n4`n0`n" -Environment $CommonEnvironment
  if ($BadSession.Output -notmatch "attention_state=malformed_session_state") { Fail "malformed session state was not conservative" }
  if (([string](Read-CallLog $CallLog)).Length -ne 0) { Fail "malformed session dispatched a child" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $UnsafeSession = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "1`n5`n0`n" -Environment $CommonEnvironment
  if ($UnsafeSession.Output -notmatch "attention_state=malformed_session_state") { Fail "unsafe session directory was accepted" }
  if (([string](Read-CallLog $CallLog)).Length -ne 0) { Fail "unsafe session directory dispatched a child" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $ApplyEof = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "1`n" -Environment (@{ TUI_FIXTURE_CALL_LOG = $CallLog; BOOTSTRAP_STUB_ACTION = "deploy_plan" })
  if ((Read-CallLog $CallLog) -match "ApplyDeploy") { Fail "EOF enabled deploy" }

  Write-Host "tui_fixture_tests=ok"
}
finally {
  if (Test-Path -LiteralPath $Base) { Remove-Item -LiteralPath $Base -Recurse -Force }
}
