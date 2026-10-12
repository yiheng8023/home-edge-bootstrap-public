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

function Get-FixtureSnapshot([string]$Root) {
  return ((Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
    if ($_.PSIsContainer) { "directory=$($_.FullName)" }
    else { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)|$($_.LastWriteTimeUtc.Ticks)" }
  }) -join "`n")
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
  New-Item -ItemType Directory -Path (Join-Path $FakeScripts "lib"),(Join-Path $FakeRepo "config"),(Join-Path $FakeRepo "adapters\merlin") | Out-Null
  Copy-Item -LiteralPath (Join-Path $Repo "PROJECT") -Destination $FakeRepo
  Set-Content -LiteralPath (Join-Path $FakeRepo "README.md") -Value "fixture" -Encoding ASCII
  Copy-Item -LiteralPath (Join-Path $Repo "scripts\lib\project-location.ps1") -Destination (Join-Path $FakeScripts "lib")
  Copy-Item -LiteralPath (Join-Path $Repo "scripts\lib\host-launcher.ps1") -Destination (Join-Path $FakeScripts "lib")
  Copy-Item -LiteralPath (Join-Path $Repo "scripts\launch-tui.ps1") -Destination $FakeScripts
  foreach ($Relative in @("bootstrap.sh","config\policy.env","adapters\merlin\bootstrap.sh")) { Set-Content -LiteralPath (Join-Path $FakeRepo $Relative) -Value "fixture" -Encoding ASCII }
  Set-Content -LiteralPath (Join-Path $FakeScripts "create-desktop-shortcut.ps1") -Value 'Add-Content -LiteralPath $env:TUI_FIXTURE_CALL_LOG -Value "desktop-shortcut"' -Encoding ASCII
  @'
param([switch]$Json, [string]$Router = "")
$Parts = @()
if ($Json) { $Parts += "-Json" }
if ($Router) { $Parts += $Router }
Add-Content -LiteralPath $env:TUI_FIXTURE_CALL_LOG -Value ("doctor " + ($Parts -join " "))
if ($env:DOCTOR_STUB_REMOVE_PROJECT -eq "1") { Remove-Item -LiteralPath (Join-Path $PSScriptRoot "..\PROJECT") -Force }
if ($env:DOCTOR_STUB_REMOVE_BOOTSTRAP -eq "1") { Remove-Item -LiteralPath (Join-Path $PSScriptRoot "run-bootstrap.ps1") -Force }
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

  @'
param([string]$Router)
Add-Content -LiteralPath $env:TUI_FIXTURE_CALL_LOG -Value ("project-probe " + $Router)
$State = if ($env:PROJECT_STUB_STATE) { $env:PROJECT_STUB_STATE } else { "not_installed" }
$Fields = [ordered]@{
  schema = if ($env:PROJECT_STUB_SCHEMA) { $env:PROJECT_STUB_SCHEMA } else { "1" }
  router = if ($env:PROJECT_STUB_ROUTER) { $env:PROJECT_STUB_ROUTER } else { $Router }
  state = $State
  reason = "fixture_observation"
  path = if ($env:PROJECT_STUB_PATH) { $env:PROJECT_STUB_PATH } else { "/jffs/home-edge-bootstrap" }
  replace_allowed = if ($env:PROJECT_STUB_ALLOWED) { $env:PROJECT_STUB_ALLOWED } elseif ($State -in @("installed", "partial")) { "1" } else { "0" }
}
if ($env:PROJECT_STUB_CHANGE_ON_SECOND -eq "1" -and @(Get-Content -LiteralPath $env:TUI_FIXTURE_CALL_LOG | Where-Object { $_ -like "project-probe *" }).Count -ge 2) { $Fields.path = "/jffs/changed" }
foreach ($Key in $Fields.Keys) {
  if ($Key -ne $env:PROJECT_STUB_OMIT) { Write-Host ("project_install_" + $Key + "=" + $Fields[$Key]) }
  if ($Key -eq $env:PROJECT_STUB_DUPLICATE) { Write-Host ("project_install_" + $Key + "=" + $Fields[$Key]) }
}
if ($env:PROJECT_STUB_EXIT) { exit [int]$env:PROJECT_STUB_EXIT }
'@ | Set-Content -LiteralPath (Join-Path $FakeScripts "check-project-installation.ps1") -Encoding ASCII
  @'
param([string]$Router, [string]$RemoteDir, [switch]$Apply, [switch]$ReplaceProject, [string]$ProjectConfirmation, [switch]$ProjectOnly)
$Parts = @()
if ($ProjectOnly) { $Parts += "-ProjectOnly" }
$Parts += @("-Router", $Router, "-RemoteDir", $RemoteDir)
if ($Apply) { $Parts += "-Apply" }
if ($ReplaceProject) { $Parts += "-ReplaceProject" }
if ($ProjectConfirmation) { $Parts += @("-ProjectConfirmation", $ProjectConfirmation) }
Add-Content -LiteralPath $env:TUI_FIXTURE_CALL_LOG -Value ("deploy-merlin " + ($Parts -join " "))
Add-Content -LiteralPath $env:TUI_FIXTURE_CALL_LOG -Value ("deploy-scope runtime=" + $env:BOOTSTRAP_INSTALL_RUNTIME + " replace_runtime=" + $env:BOOTSTRAP_REPLACE_RUNTIME + " replace_core=" + $env:BOOTSTRAP_REPLACE_CORE + " include_bundle=" + $env:INCLUDE_BUNDLE)
Write-Host ("deploy_state=" + $(if ($Apply) { "applied" } else { "plan" }))
Write-Host ("router=" + $Router)
Write-Host ("remote_dir=" + $RemoteDir)
if (-not $Apply) { Write-Host 'runtime_assets_effect=preserve'; Write-Host 'integration_effect=project_managed_configuration_may_change' }
'@ | Set-Content -LiteralPath (Join-Path $FakeScripts "deploy-merlin.ps1") -Encoding ASCII

  $SupportStub = Join-Path $FakeScripts "export-support-bundle.ps1"
  $SupportMissing = "$SupportStub.missing"
  Move-Item -LiteralPath $SupportStub -Destination $SupportMissing
  if ((Invoke-TuiProcess -Script $FakeTui -Arguments @("-Help")).Status -ne 0) { Fail "help should bypass startup prerequisites" }
  if ((Invoke-TuiProcess -Script $FakeTui -Arguments @("-Version")).Status -ne 0) { Fail "version should bypass startup prerequisites" }
  $StartupMissing = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "0`n"
  if ($StartupMissing.Status -ne 0) { Fail "missing optional operation prevented menu startup" }
  $Unavailable = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "5`n0`n"
  if ($Unavailable.Status -ne 2 -or $Unavailable.Output -notmatch "capability_state=unavailable") { Fail "missing selected capability was not explained" }
  Move-Item -LiteralPath $SupportMissing -Destination $SupportStub

  $Default = Invoke-TuiProcess -Script $FakeTui -Arguments @("-NoColor") -InputText "0`n"
  $DesktopChoiceLog = Join-Path $Base "desktop-choice.log"
  $DesktopChoice = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "8`n0`n" -Environment @{TUI_FIXTURE_CALL_LOG=$DesktopChoiceLog}
  if ($DesktopChoice.Status -ne 0 -or (Get-Content -Raw -LiteralPath $DesktopChoiceLog).Trim() -ne "desktop-shortcut") { Fail "desktop setup was not delegated from the menu" }
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
  foreach ($Number in @(1, 2, 3, 4, 5, 6, 7, 8, 0)) {
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

  $ChineseHelp = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("SG9tZSBFZGdlIOacrOWcsOW4ruWKqQ=="))
  $Snapshot = Get-FixtureSnapshot $FakeRepo
  foreach ($Alias in @("H", "?", "help", "6")) {
    Set-Content -LiteralPath $CallLog -Value "" -NoNewline
    $LocalHelp = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "$Alias`n0`n" -Environment $CommonEnvironment
    if ($LocalHelp.Status -ne 0 -or $LocalHelp.Output -notmatch "Home Edge local help") { Fail "local help alias failed: $Alias" }
    foreach ($Expected in @("project_dir=$FakeRepo", "doc=$(Join-Path $FakeRepo 'docs\RUNBOOK.md')", "First installation:", "Already installed:", "APPLY", "ENABLE", "DECOMMISSION", "EOF", "H / ? / help. Local help", "9 / L / language.")) {
      if ($LocalHelp.Output -notmatch [regex]::Escape($Expected)) { Fail "local help missing $Expected" }
    }
    if ((Read-CallLog $CallLog).Length -ne 0) { Fail "help dispatched a child: $Alias" }
  }
  $CliEnglishHelp = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Help") -Environment $CommonEnvironment
  if ($Help.Output -notmatch [regex]::Escape($ChineseHelp) -or $CliEnglishHelp.Output -notmatch "Home Edge local help") { Fail "CLI help did not follow language" }
  $ChineseAssetScope = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("6L+Q6KGM5pe25ZKM5qC45b+D6LWE5Lqn"))
  $ChineseConfigScope = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("562W55Wl44CB6ZuG5oiQ5ZKM6YWN572u"))
  $OverbroadScope = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("5L+d55WZ55So5oi36YWN572u"))
  if (-not $Help.Output.Contains($ChineseAssetScope) -or -not $Help.Output.Contains($ChineseConfigScope) -or $Help.Output.Contains($OverbroadScope)) { Fail "Chinese help conceals project-managed configuration effects" }
  foreach ($Alias in @("L", "language", "9")) {
    Set-Content -LiteralPath $CallLog -Value "" -NoNewline
    $LanguageToggle = Invoke-TuiProcess -Script $FakeTui -Arguments @("-NoColor") -InputText "$Alias`nH`n$Alias`n?`n0`n" -Environment $CommonEnvironment
    if ($LanguageToggle.Status -ne 0 -or $LanguageToggle.Output -notmatch "language=en" -or $LanguageToggle.Output -notmatch "language=zh-CN" -or $LanguageToggle.Output -notmatch "Home Edge local help" -or $LanguageToggle.Output -notmatch [regex]::Escape($ChineseHelp) -or $LanguageToggle.Output -notmatch "1. Start or resume guided bootstrap") { Fail "language toggle did not immediately localize menu/help: $Alias" }
    if ((Read-CallLog $CallLog).Length -ne 0) { Fail "language/help dispatched a child: $Alias" }
  }
  $EnglishToChinese = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "L`nhelp`n" -Environment $CommonEnvironment
  if ($EnglishToChinese.Status -ne 0 -or $EnglishToChinese.Output -notmatch "language=zh-CN" -or $EnglishToChinese.Output -notmatch [regex]::Escape($ChineseHelp)) { Fail "English-to-Chinese toggle or EOF failed" }
  $LocalInvalid = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "invalid-choice`n" -Environment $CommonEnvironment
  if ($LocalInvalid.Status -ne 0 -or $LocalInvalid.Output -notmatch "Invalid selection.") { Fail "invalid choice/EOF was not handled" }
  if ((Read-CallLog $CallLog).Length -ne 0 -or (Get-FixtureSnapshot $FakeRepo) -cne $Snapshot) { Fail "local help/language/EOF changed fixture project or dispatched a child" }

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
  $InvalidChoice = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "invalid-choice`n0`n" -Environment $CommonEnvironment
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
  foreach ($Expected in @("expected_effect=apply_reviewed_deployment_plan", "rollback_path=& ", ("'" + (Join-Path (Split-Path $FakeTui -Parent) 'rollback-merlin.ps1') + "' '-Router' 'user@192.168.50.1'"), "session_destination=C:\fixture\session", "log_destination=C:\fixture\bootstrap.log")) {
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
  $ExpectedResume = "'" + (Join-Path (Split-Path $FakeTui -Parent) 'run-bootstrap.ps1') + "' -NoPause -Router 'user@192.168.50.1'"
  if ($ChildError.Output -notmatch "safe_resume_command=& " -or $ChildError.Output.Replace("''", "'") -notmatch [regex]::Escape($ExpectedResume)) { Fail "safe resume command did not bind its project and target" }

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
  $Snapshot = Get-FixtureSnapshot $FakeRepo
  $SwitchSession = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "3`n2`nL`nH`n3`n9`nhelp`n3`n0`n" -Environment $CommonEnvironment
  if ($SwitchSession.Status -ne 0 -or ([regex]::Matches($SwitchSession.Output, "next_action_command=json-resume-command")).Count -ne 3 -or ([regex]::Matches($SwitchSession.Output, "existing_session=2")).Count -ne 1) { Fail "language/help lost selected session or router" }
  if ((Read-CallLog $CallLog).Length -ne 0 -or (Get-FixtureSnapshot $FakeRepo) -cne $Snapshot) { Fail "language/help/session display changed the fixture project" }
  $RouterToggle = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor", "-Router", "user@192.168.50.1") -InputText "L`nH`n9`n2`n0`n" -Environment $CommonEnvironment
  if ((Read-CallLog $CallLog).Trim() -ne "doctor -Json user@192.168.50.1") { Fail "language/help lost CLI router" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $SelectedResume = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-NoColor") -InputText "3`n2`nL`nH`n9`n1`nWRONG`n0`n" -Environment (@{ TUI_FIXTURE_CALL_LOG = $CallLog; BOOTSTRAP_STUB_ACTION = "deploy_plan" })
  $SelectedCalls = Read-CallLog $CallLog
  if ($SelectedCalls -notmatch "run-bootstrap -NoPause -SessionDir .*02-json json-user@192.168.50.3") { Fail "selected session did not infer router and preserve session directory" }
  $ExpectedSelectedResume = "'" + (Join-Path (Split-Path $FakeTui -Parent) 'run-bootstrap.ps1') + "' -NoPause -ApplyDeploy -SessionDir '" + $SessionJson + "' -Router 'json-user@192.168.50.3'"
  if ($SelectedResume.Output -notmatch "exact_command=& " -or $SelectedResume.Output.Replace("''", "'") -notmatch [regex]::Escape($ExpectedSelectedResume)) { Fail "selected-session command did not bind its project, session and router" }

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

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $Existing = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText "1`n0`n" -Environment @{ TUI_FIXTURE_CALL_LOG=$CallLog; PROJECT_STUB_STATE="installed"; BOOTSTRAP_STUB_ACTION="deploy_plan" }
  if ($Existing.Status -ne 0 -or $Existing.Output -notmatch "explicitly choose R" -or (Read-CallLog $CallLog) -match "ApplyDeploy|deploy-merlin") { Fail "already installed default silently redeployed" }
  foreach ($State in @("installed", "partial")) {
    foreach ($Inputs in @("R`nWRONG`n0`n", "R`nreplace`n0`n", "R`nREPLACE `n0`n", "R`nREPLACE`nWRONG`n0`n", "R`nREPLACE`napply`n0`n", "R`nREPLACE`nAPPLY `n0`n", "R`n", "R`nREPLACE`n")) {
      Set-Content -LiteralPath $CallLog -Value "" -NoNewline
      $CancelRefresh = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText $Inputs -Environment @{ TUI_FIXTURE_CALL_LOG=$CallLog; PROJECT_STUB_STATE=$State }
      if ($CancelRefresh.Status -ne 0 -or (Read-CallLog $CallLog) -match "-Apply|-ReplaceProject") { Fail "project refresh cancellation/EOF allowed a write ($State)" }
      if ((Read-CallLog $CallLog) -notmatch "project-probe user@192.168.50.1" -or (Read-CallLog $CallLog) -notmatch "deploy-merlin -ProjectOnly -Router") { Fail "refresh did not probe and plan first ($State)" }
    }
    Set-Content -LiteralPath $CallLog -Value "" -NoNewline
    $Refresh = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText "R`nREPLACE`nAPPLY`n0`n" -Environment @{ TUI_FIXTURE_CALL_LOG=$CallLog; PROJECT_STUB_STATE=$State; BOOTSTRAP_INSTALL_RUNTIME="1"; BOOTSTRAP_REPLACE_RUNTIME="1"; BOOTSTRAP_REPLACE_CORE="1"; INCLUDE_BUNDLE="1" }
    $RefreshCalls = Read-CallLog $CallLog
    if ($Refresh.Status -ne 0 -or $RefreshCalls -notmatch "deploy-merlin -ProjectOnly -Router user@192.168.50.1 -RemoteDir /jffs/home-edge-bootstrap -Apply -ReplaceProject -ProjectConfirmation REPLACE") { Fail "double confirmation did not refresh owned project ($State)" }
    if (([regex]::Matches($RefreshCalls, "deploy-scope runtime=0 replace_runtime=0 replace_core=0 include_bundle=0")).Count -ne 2 -or $Refresh.Output -notmatch "project_backup_path=/jffs/home-edge-bootstrap.prev") { Fail "project refresh scope or backup disclosure incorrect ($State)" }
    $DisplayedCommand = [regex]::Match($Refresh.Output, "(?m)^exact_command=(.*)$").Groups[1].Value.TrimEnd("`r")
    if ($DisplayedCommand -notmatch "BOOTSTRAP_REPLACE_CORE" -or $DisplayedCommand -notmatch "-Command") { Fail "displayed refresh command omitted isolated environment scope" }
    $ReplayScript = Join-Path $Base "replay-scoped-command.ps1"
    Set-Content -LiteralPath $ReplayScript -Value $DisplayedCommand -Encoding ASCII
    Set-Content -LiteralPath $CallLog -Value "" -NoNewline
    $Replay = Invoke-TuiProcess -Script $ReplayScript -Environment @{ TUI_FIXTURE_CALL_LOG=$CallLog; BOOTSTRAP_INSTALL_RUNTIME="1"; BOOTSTRAP_REPLACE_RUNTIME="1"; BOOTSTRAP_REPLACE_CORE="1"; INCLUDE_BUNDLE="1" }
    if ($Replay.Status -ne 0 -or (Read-CallLog $CallLog) -notmatch "deploy-scope runtime=0 replace_runtime=0 replace_core=0 include_bundle=0" -or (Read-CallLog $CallLog) -notmatch "-Apply -ReplaceProject -ProjectConfirmation REPLACE") { Fail "copied scoped refresh command changed authority or quoting: status=$($Replay.Status) error=$($Replay.Error) output=$($Replay.Output) calls=$(Read-CallLog $CallLog)" }

  }
  foreach ($BadProbe in @(@{PROJECT_STUB_STATE="unknown"}, @{PROJECT_STUB_STATE="installed";PROJECT_STUB_EXIT="1"}, @{PROJECT_STUB_SCHEMA="2"}, @{PROJECT_STUB_ROUTER="other@192.168.50.1"}, @{PROJECT_STUB_PATH="/jffs/../wrong"}, @{PROJECT_STUB_STATE="unrecognized"}, @{PROJECT_STUB_STATE="INSTALLED"}, @{PROJECT_STUB_PATH="/JFFS/wrong"}, @{PROJECT_STUB_ALLOWED="2"}, @{PROJECT_STUB_STATE="partial";PROJECT_STUB_ALLOWED="0"})) {
    Set-Content -LiteralPath $CallLog -Value "" -NoNewline
    $BadProbe.TUI_FIXTURE_CALL_LOG=$CallLog
    $BlockedRefresh = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText "R`nREPLACE`nAPPLY`n0`n" -Environment $BadProbe
    if ((Read-CallLog $CallLog) -match "deploy-merlin|run-bootstrap") { Fail "unknown/foreign installation enabled deployment" }
  }
  foreach ($Key in @("schema", "router", "state", "reason", "path", "replace_allowed")) {
    foreach ($Format in @("PROJECT_STUB_DUPLICATE", "PROJECT_STUB_OMIT")) {
      Set-Content -LiteralPath $CallLog -Value "" -NoNewline
      $BadEnvironment = @{ TUI_FIXTURE_CALL_LOG=$CallLog; PROJECT_STUB_STATE="installed" }
      $BadEnvironment[$Format]=$Key
      $MalformedProbe = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText "R`nREPLACE`nAPPLY`n0`n" -Environment $BadEnvironment
      if ($MalformedProbe.Output -notmatch "attention_state=invalid_installation_probe" -or (Read-CallLog $CallLog) -match "deploy-merlin") { Fail "missing/duplicate critical probe field was accepted: $Key" }
    }
  }
  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $NotInstalledRefresh = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText "R`n0`n" -Environment $CommonEnvironment
  if ($NotInstalledRefresh.Output -notmatch "Choose 1 for first installation" -or (Read-CallLog $CallLog) -match "deploy-merlin") { Fail "R interpreted missing project as replacement" }
  foreach ($State in @("unknown", "partial", "installed")) {
    Set-Content -LiteralPath $CallLog -Value "" -NoNewline
    $UnsafeEnable = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText "1`nENABLE`n0`n" -Environment @{ TUI_FIXTURE_CALL_LOG=$CallLog; PROJECT_STUB_STATE=$State; PROJECT_STUB_ALLOWED="0"; BOOTSTRAP_STUB_ACTION="enable_live_self_heal" }
    if ((Read-CallLog $CallLog) -match "EnableLiveSelfHeal|ApplyDeploy") { Fail "unknown/foreign/partial installation enabled write ($State)" }
  }
  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $FailureThenHelp = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText "1`nH`nL`n" -Environment @{ TUI_FIXTURE_CALL_LOG=$CallLog; BOOTSTRAP_STUB_EXIT="17" }
  if ($FailureThenHelp.Status -ne 17) { Fail "help/language erased the preceding child failure" }
  $ProbeFile = Join-Path $FakeScripts "check-project-installation.ps1"
  Move-Item -LiteralPath $ProbeFile -Destination "$ProbeFile.missing"
  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $MissingProbe = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText "1`nH`nL`nR`n0`n" -Environment $CommonEnvironment
  if ($MissingProbe.Output -notmatch "capability_state=unavailable" -or $MissingProbe.Output -notmatch "Home Edge local help" -or (Read-CallLog $CallLog).Length -ne 0) { Fail "missing probe blocked local UI or dispatched an operation" }
  Move-Item -LiteralPath "$ProbeFile.missing" -Destination $ProbeFile

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $ChangedProbe = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText "R`nREPLACE`nAPPLY`n0`n" -Environment @{ TUI_FIXTURE_CALL_LOG=$CallLog; PROJECT_STUB_STATE="installed"; PROJECT_STUB_CHANGE_ON_SECOND="1" }
  if ($ChangedProbe.Output -notmatch "attention_state=installation_probe_changed" -or (Read-CallLog $CallLog) -match "-Apply -ReplaceProject") { Fail "changed refresh path reached fake deploy apply" }

  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $RemovedProject = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText "2`n1`nH`nL`n0`n" -Environment @{ TUI_FIXTURE_CALL_LOG=$CallLog; DOCTOR_STUB_REMOVE_PROJECT="1" }
  if ($RemovedProject.Output -notmatch "condition_state=project_degraded" -or $RemovedProject.Output -notmatch "Home Edge local help" -or $RemovedProject.Output -notmatch "language=zh-CN" -or (Read-CallLog $CallLog) -match "run-bootstrap ") { Fail "removed PROJECT did not stop dependent work while retaining local UI" }
  Copy-Item -LiteralPath (Join-Path $Repo "PROJECT") -Destination $FakeRepo

  $BootstrapFile = Join-Path $FakeScripts "run-bootstrap.ps1"
  Copy-Item -LiteralPath $BootstrapFile -Destination "$BootstrapFile.saved"
  Set-Content -LiteralPath $CallLog -Value "" -NoNewline
  $RemovedOperation = Invoke-TuiProcess -Script $FakeTui -Arguments @("-Language", "en", "-Router", "user@192.168.50.1") -InputText "1`nH`nL`n0`n" -Environment @{ TUI_FIXTURE_CALL_LOG=$CallLog; DOCTOR_STUB_REMOVE_BOOTSTRAP="1" }
  if ($RemovedOperation.Output -notmatch "capability_state=unavailable" -or $RemovedOperation.Output -notmatch "Home Edge local help" -or (Read-CallLog $CallLog) -match "run-bootstrap ") { Fail "removed operation was invoked or blocked local UI" }
  Move-Item -LiteralPath "$BootstrapFile.saved" -Destination $BootstrapFile
  Write-Host "tui_fixture_installation_guard_tests=ok"

  Write-Host "tui_fixture_tests=ok"
}
finally {
  if (Test-Path -LiteralPath $Base) { Remove-Item -LiteralPath $Base -Recurse -Force }
}
