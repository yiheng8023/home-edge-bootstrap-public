param(
  [string]$Language = "zh-CN",
  [string]$Router = "",
  [switch]$NoColor,
  [switch]$Help,
  [switch]$Version
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:SelectedSessionDir = ""
$script:SelectedStateFile = ""
$script:LastActionStatus = 0
$script:Interrupted = $false

function Decode-Text([string]$Value) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
function Show-Usage {
  Write-Host "usage: powershell -File scripts\tui.ps1 [-Language zh-CN|en] [-Router <ssh-user>@<router-ip>] [-NoColor] [-Help] [-Version]"
  Write-Host ""
  Write-Host "Numbered guide over the existing Home Edge bootstrap scripts. Help and version"
  Write-Host "do not contact a router or the Internet."
}
function Show-Version {
  $Value = "development"
  $VersionPath = Join-Path $Repo "VERSION"
  if (Test-Path -LiteralPath $VersionPath -PathType Leaf) {
    $Candidate = (Get-Content -LiteralPath $VersionPath -TotalCount 1).Trim()
    if ($Candidate) { $Value = $Candidate }
  }
  Write-Host "home-edge-bootstrap $Value"
}
function Test-RouterTarget([string]$Target) {
  if ($Target -notmatch '^[A-Za-z0-9_.-]+@[A-Za-z0-9][A-Za-z0-9.-]*$') { return $false }
  $HostPart = ($Target -split '@', 2)[1]
  return -not ($HostPart.StartsWith('.') -or $HostPart.EndsWith('.') -or $HostPart.Contains('..'))
}

if ($Language -notin @("zh-CN", "en")) { [Console]::Error.WriteLine("unsupported language: $Language"); exit 2 }
if ($Router -and -not (Test-RouterTarget $Router)) { [Console]::Error.WriteLine("invalid router target: $Router"); exit 2 }
if ($Help) { Show-Usage; exit 0 }
if ($Version) { Show-Version; exit 0 }

function Test-Startup {
  if (-not (Get-Command powershell -ErrorAction SilentlyContinue)) {
    Write-Host "startup_state=failed"
    Write-Host "missing_prerequisite=powershell"
    return $false
  }
  foreach ($Name in @("doctor.ps1", "run-bootstrap.ps1", "check-no-wall-readiness.ps1", "export-support-bundle.ps1")) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $Name) -PathType Leaf)) {
      Write-Host "startup_state=failed"
      Write-Host "missing_prerequisite=scripts/$Name"
      return $false
    }
  }
  return $true
}
if (-not (Test-Startup)) { exit 2 }

$Zh = @{
  Title = Decode-Text "IyBIb21lIEVkZ2Ug5byV5a+85Zmo"
  Start = Decode-Text "MS4g5byA5aeL5oiW5o6l57ut5byV5a+85byP6YWN572u"
  Doctor = Decode-Text "Mi4g6L+Q6KGM5Y+q6K+76K+K5pat"
  Session = Decode-Text "My4g5p+l55yL5b2T5YmNIGJvb3RzdHJhcCDkvJror53nirbmgIE="
  Bundle = Decode-Text "NC4g6aqM6K+B56a757q/6L+Q6KGM5pe2IGJ1bmRsZQ=="
  Support = Decode-Text "NS4g5a+85Ye66ISx5pWP5pSv5oyB5YyF"
  Help = Decode-Text "Ni4g5p+l55yL5biu5Yqp5LiO5a6J5YWo6L6555WM"
  Exit = Decode-Text "MC4g5LiN5YGa5L+u5pS55bm26YCA5Ye6"
  Prompt = Decode-Text "6K+36YCJ5oupOiA="
  Invalid = Decode-Text "5peg5pWI6YCJ5oup44CC"
  RouterPrompt = Decode-Text "6K+36L6T5YWl6Lev55Sx5ZmoIFNTSCDnm67moIfvvIh1c2VyQGlw77yJOiA="
  RouterInvalid = Decode-Text "6Lev55Sx5Zmo55uu5qCH5qC85byP5peg5pWI44CC"
  ApplyPrompt = Decode-Text "5Y2z5bCG5omn6KGM6YOo572y44CC6L6T5YWlIEFQUExZIOehruiupO+8jOWFtuS7lui+k+WFpeWPlua2iDog"
  EnablePrompt = Decode-Text "5Y2z5bCG5byA5ZCv55yf5a6e6Ieq5oSI44CC6L6T5YWlIEVOQUJMRSDnoa7orqTvvIzlhbbku5bovpPlhaXlj5bmtog6IA=="
  Cancelled = Decode-Text "5pON5L2c5bey5Y+W5raI44CC"
  Safety = Decode-Text "5biu5Yqp5LiO5a6J5YWo6L6555WM77ya5Y+q6K+75pON5L2c5Y+v55u05o6l6L+Q6KGM77yb6YOo572y5ZKM55yf5a6e6Ieq5oSI5b+F6aG76L6T5YWl56Gu6K6k5Luk54mM44CC"
}

function Show-Menu {
  if ($Language -eq "en") {
    Write-Host "# Home Edge Guide"
    Write-Host "1. Start or resume guided bootstrap"
    Write-Host "2. Run read-only diagnosis"
    Write-Host "3. View current bootstrap session state"
    Write-Host "4. Verify offline runtime bundle"
    Write-Host "5. Export a redacted support bundle"
    Write-Host "6. Show help and safety boundaries"
    Write-Host "0. Exit without changes"
    return "Select: "
  }
  foreach ($Key in @("Title", "Start", "Doctor", "Session", "Bundle", "Support", "Help", "Exit")) { Write-Host $Zh[$Key] }
  return $Zh.Prompt
}

function Read-StateFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try {
    $Values = [ordered]@{}
    if ([IO.Path]::GetExtension($Path) -eq ".json") {
      $Json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
      foreach ($Key in @("bootstrap_state", "phase", "router", "next_action_code", "next_action_command", "session_dir", "log_dir", "log_path", "updated_at")) {
        $Values[$Key] = [string]$Json.$Key
      }
    }
    elseif ([IO.Path]::GetExtension($Path) -eq ".env") {
      foreach ($Line in Get-Content -LiteralPath $Path) {
        if ($Line -match '^([A-Za-z0-9_]+)=(.*)$' -and $Matches[1] -in @("bootstrap_state", "phase", "router", "next_action_code", "next_action_command", "session_dir", "log_dir", "log_path", "updated_at")) {
          $Values[$Matches[1]] = $Matches[2]
        }
      }
    }
    else { return $null }
    if (-not $Values.bootstrap_state -or -not $Values.router) { return $null }
    return [pscustomobject]$Values
  }
  catch { return $null }
}
function Test-KnownNextCode([string]$Code) {
  if (-not $Code) { return $true }
  if ($Code -like "installation_closeout_*") { return $true }
  return $Code -in @("none", "enable_router_prereqs", "resolve_action_findings", "review_baseline_findings", "deploy_plan", "store_or_import_subscription", "store_subscription_for_managed_switching", "inspect_self_heal_dry_run", "enable_live_self_heal", "monitor_live_managed", "inspect_audit_log", "manual_prerequisite_setup", "step_failed", "inspect_logs", "resume")
}
function Get-SessionRecords {
  $Records = @()
  $Root = Join-Path $Repo "logs\bootstrap"
  if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $Records }
  $Index = 0
  foreach ($Directory in @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name)) {
    $StatePath = if (Test-Path -LiteralPath (Join-Path $Directory.FullName "state.json") -PathType Leaf) { Join-Path $Directory.FullName "state.json" } elseif (Test-Path -LiteralPath (Join-Path $Directory.FullName "state.env") -PathType Leaf) { Join-Path $Directory.FullName "state.env" } else { "" }
    if (-not $StatePath) { continue }
    $Index++
    $State = Read-StateFile $StatePath
    $DisplayRouter = if ($null -ne $State) { $State.router } else { "<unknown>" }
    $DisplayState = if ($null -ne $State) { $State.bootstrap_state } else { "malformed" }
    Write-Host "existing_session=$Index router=$DisplayRouter bootstrap_state=$DisplayState session_dir=$($Directory.FullName)"
    $Records += [pscustomobject]@{ Index = $Index; Directory = $Directory.FullName; StatePath = $StatePath; State = $State }
  }
  return $Records
}
function Ensure-Router {
  if ($script:Router) { return $true }
  $Records = @(Get-SessionRecords)
  if ($Records.Count -gt 0) {
    if ($Language -eq "en") { [Console]::Write("Select an existing session number, or press Enter to type a router target: ") }
    else { [Console]::Write((Decode-Text "6YCJ5oup546w5pyJ5Lya6K+d57yW5Y+377yM5oiW55u05o6l5Zue6L2m5ZCO6L6T5YWl6Lev55Sx5Zmo55uu5qGHOiA=")) }
    $Selection = [Console]::In.ReadLine()
    if ($null -eq $Selection) { return $false }
    if ($Selection) {
      $Number = 0
      if (-not [int]::TryParse($Selection, [ref]$Number)) { Write-Host "attention_state=invalid_session_selection"; return $false }
      $Record = @($Records | Where-Object Index -eq $Number)[0]
      if ($null -eq $Record) { Write-Host "attention_state=invalid_session_selection"; return $false }
      if ((Split-Path -Leaf $Record.Directory) -notmatch '^[A-Za-z0-9_.-]+$') { Write-Host "attention_state=malformed_session_state"; return $false }
      if ($null -eq $Record.State -or -not (Test-RouterTarget $Record.State.router)) { Write-Host "attention_state=malformed_session_state"; return $false }
      $script:Router = $Record.State.router
      $script:SelectedSessionDir = $Record.Directory
      $script:SelectedStateFile = $Record.StatePath
      return $true
    }
  }
  if ($Language -eq "en") { [Console]::Write("Enter router SSH target (user@ip): ") } else { [Console]::Write($Zh.RouterPrompt) }
  $Candidate = [Console]::In.ReadLine()
  if ($null -eq $Candidate -or -not (Test-RouterTarget $Candidate)) {
    if ($Language -eq "en") { Write-Host "Invalid router target." } else { Write-Host $Zh.RouterInvalid }
    return $false
  }
  $script:Router = $Candidate
  return $true
}

function Invoke-ChildScript {
  param([string]$Action, [string]$SafeResumeCommand, [bool]$WriteStarted, [string]$Script, [string[]]$Arguments = @())
  $Lines = [Collections.Generic.List[string]]::new()
  $PowerShellArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Script) + $Arguments
  & powershell @PowerShellArguments 2>&1 | ForEach-Object { $Text = [string]$_; $Lines.Add($Text); Write-Host $Text }
  $Status = $LASTEXITCODE
  if ($null -eq $Status) { $Status = 1 }
  $script:LastActionStatus = [int]$Status
  if ($Status -ne 0) {
    Write-Host "failed_action=$Action"
    Write-Host "child_exit_code=$Status"
    Write-Host "safe_resume_command=$SafeResumeCommand"
    if ($WriteStarted) { Write-Host "write_action_started=true" }
  }
  return [pscustomobject]@{ Status = [int]$Status; Output = ($Lines -join [Environment]::NewLine) }
}
function Invoke-Doctor {
  $Arguments = @("-Json")
  $Resume = "powershell -File scripts\doctor.ps1 -Json"
  if ($script:Router) { $Arguments += @("-Router", $script:Router); $Resume += " -Router $($script:Router)" }
  return Invoke-ChildScript -Action "doctor" -SafeResumeCommand $Resume -WriteStarted $false -Script (Join-Path $PSScriptRoot "doctor.ps1") -Arguments $Arguments
}
function Get-BootstrapCommand([string]$Flag = "") {
  $Command = "powershell -File scripts\run-bootstrap.ps1 -NoPause"
  if ($Flag) { $Command += " $Flag" }
  if ($script:SelectedSessionDir) { $Command += " -SessionDir 'logs/bootstrap/$(Split-Path -Leaf $script:SelectedSessionDir)'" }
  return "$Command -Router $($script:Router)"
}
function Invoke-Bootstrap([string]$Action, [string]$Flag = "", [bool]$WriteStarted = $false) {
  $Arguments = @("-NoPause")
  if ($Flag) { $Arguments += $Flag }
  if ($script:SelectedSessionDir) { $Arguments += @("-SessionDir", $script:SelectedSessionDir) }
  $Arguments += @("-Router", $script:Router)
  return Invoke-ChildScript -Action $Action -SafeResumeCommand (Get-BootstrapCommand $Flag) -WriteStarted $WriteStarted -Script (Join-Path $PSScriptRoot "run-bootstrap.ps1") -Arguments $Arguments
}
function Get-OutputValue([string]$Text, [string]$Key) {
  $Match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Key))=(.*)$")
  if ($Match.Success) { return $Match.Groups[1].Value.Trim() }
  return ""
}
function Show-WriteDisclosure([string]$Effect, [string]$ExactCommand, [string]$Output) {
  $SessionDestination = Get-OutputValue $Output "session_dir"
  $LogDestination = Get-OutputValue $Output "log_path"
  if (-not $SessionDestination) { $SessionDestination = if ($script:SelectedSessionDir) { $script:SelectedSessionDir } else { "unknown" } }
  if (-not $LogDestination) { $LogDestination = "unknown" }
  Write-Host "exact_command=$ExactCommand"
  Write-Host "expected_effect=$Effect"
  Write-Host "rollback_path=powershell -File scripts\rollback-merlin.ps1 -Router $($script:Router)"
  Write-Host "session_destination=$SessionDestination"
  Write-Host "log_destination=$LogDestination"
}

function Start-OrResume {
  $script:LastActionStatus = 0
  if (-not (Ensure-Router)) { return }
  $DoctorResult = Invoke-Doctor
  if ($DoctorResult.Status -ne 0) { return }
  $BootstrapResult = Invoke-Bootstrap -Action "bootstrap_read_only"
  if ($BootstrapResult.Status -ne 0) { return }
  $BootstrapState = Get-OutputValue $BootstrapResult.Output "bootstrap_state"
  $NextCode = Get-OutputValue $BootstrapResult.Output "next_action_code"
  if (-not $BootstrapState) { Write-Host "attention_state=malformed_child_state"; return }
  if ($BootstrapState -eq "pass") { return }
  switch ($NextCode) {
    "deploy_plan" {
      $Exact = Get-BootstrapCommand "-ApplyDeploy"
      Show-WriteDisclosure "apply_reviewed_deployment_plan" $Exact $BootstrapResult.Output
      if ($Language -eq "en") { [Console]::Write("Deployment is ready. Type APPLY to confirm; anything else cancels: ") } else { [Console]::Write($Zh.ApplyPrompt) }
      $Confirmation = [Console]::In.ReadLine()
      if ($Confirmation -cne "APPLY") { if ($Language -eq "en") { Write-Host "Action cancelled." } else { Write-Host $Zh.Cancelled }; return }
      [void](Invoke-Bootstrap -Action "apply_deploy" -Flag "-ApplyDeploy" -WriteStarted $true)
    }
    "enable_live_self_heal" {
      $Exact = Get-BootstrapCommand "-EnableLiveSelfHeal"
      Show-WriteDisclosure "enable_live_self_heal" $Exact $BootstrapResult.Output
      if ($Language -eq "en") { [Console]::Write("Live self-heal is ready. Type ENABLE to confirm; anything else cancels: ") } else { [Console]::Write($Zh.EnablePrompt) }
      $Confirmation = [Console]::In.ReadLine()
      if ($Confirmation -cne "ENABLE") { if ($Language -eq "en") { Write-Host "Action cancelled." } else { Write-Host $Zh.Cancelled }; return }
      [void](Invoke-Bootstrap -Action "enable_live_self_heal" -Flag "-EnableLiveSelfHeal" -WriteStarted $true)
    }
    default {
      if (-not (Test-KnownNextCode $NextCode)) { Write-Host "attention_state=unknown_next_action" }
      foreach ($Line in ($BootstrapResult.Output -split "`r?`n")) { if ($Line -match '^(next_action_command|session_dir|log_path)=') { Write-Host $Line } }
    }
  }
}

function Show-SessionState {
  $script:LastActionStatus = 0
  if (-not (Ensure-Router)) { return }
  $StatePath = $script:SelectedStateFile
  if (-not $StatePath) {
    $RouterId = $script:Router -replace '[^A-Za-z0-9_.-]', '_'
    $StateDir = Join-Path $Repo "logs\bootstrap\$RouterId"
    if (Test-Path -LiteralPath (Join-Path $StateDir "state.json") -PathType Leaf) { $StatePath = Join-Path $StateDir "state.json" }
    elseif (Test-Path -LiteralPath (Join-Path $StateDir "state.env") -PathType Leaf) { $StatePath = Join-Path $StateDir "state.env" }
  }
  $State = if ($StatePath) { Read-StateFile $StatePath } else { $null }
  if ($null -eq $State -or -not (Test-RouterTarget $State.router)) { Write-Host "attention_state=malformed_session_state"; return }
  foreach ($Key in @("bootstrap_state", "phase", "router", "next_action_code", "next_action_command", "session_dir", "log_dir", "log_path", "updated_at")) {
    $Value = [string]$State.$Key
    if ($Value) { Write-Host "$Key=$Value" }
  }
  if (-not (Test-KnownNextCode $State.next_action_code)) { Write-Host "attention_state=unknown_session_state" }
}
function Verify-OfflineBundle { [void](Invoke-ChildScript -Action "verify_offline_bundle" -SafeResumeCommand "powershell -File scripts\check-no-wall-readiness.ps1" -WriteStarted $false -Script (Join-Path $PSScriptRoot "check-no-wall-readiness.ps1")) }
function Export-SupportBundle {
  $Arguments = @(); $Resume = "powershell -File scripts\export-support-bundle.ps1"
  if ($script:Router) { $Arguments += @("-Router", $script:Router); $Resume += " -Router $($script:Router)" }
  [void](Invoke-ChildScript -Action "export_support_bundle" -SafeResumeCommand $Resume -WriteStarted $false -Script (Join-Path $PSScriptRoot "export-support-bundle.ps1") -Arguments $Arguments)
}
function Show-SafetyHelp {
  $script:LastActionStatus = 0; Show-Usage
  if ($Language -eq "en") { Write-Host "Read-only actions may run directly. Deploy and live self-heal require confirmation tokens." } else { Write-Host $Zh.Safety }
}

try {
  [Console]::CancelKeyPress += { param($Sender, $EventArgs); $EventArgs.Cancel = $true; $script:Interrupted = $true }
}
catch { }

while ($true) {
  if ($script:Interrupted) { exit 130 }
  $Prompt = Show-Menu
  [Console]::Write($Prompt)
  $Choice = [Console]::In.ReadLine()
  if ($null -eq $Choice -or $Choice -eq "0") { exit $script:LastActionStatus }
  switch ($Choice) {
    "1" { Start-OrResume }
    "2" { [void](Invoke-Doctor) }
    "3" { Show-SessionState }
    "4" { Verify-OfflineBundle }
    "5" { Export-SupportBundle }
    "6" { Show-SafetyHelp }
    default { if ($Language -eq "en") { Write-Host "Invalid selection." } else { Write-Host $Zh.Invalid } }
  }
  if ($script:Interrupted) { exit 130 }
  Write-Host ""
}
