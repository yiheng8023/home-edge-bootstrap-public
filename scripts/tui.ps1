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
$Repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$script:SelectedSessionDir = ""
$script:SelectedStateFile = ""
$script:LastActionStatus = 0
$script:Interrupted = $false
$script:PowerShellExecutable = if (Test-Path -LiteralPath (Join-Path $PSHOME "powershell.exe")) { Join-Path $PSHOME "powershell.exe" } elseif (Test-Path -LiteralPath (Join-Path $PSHOME "pwsh.exe")) { Join-Path $PSHOME "pwsh.exe" } else { "powershell" }

function Decode-Text([string]$Value) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
function Quote-CommandArgument([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
function Get-ChildCommand([string]$Script, [string[]]$Arguments = @(), [hashtable]$EnvironmentOverrides = @{}) {
  if ($EnvironmentOverrides.Count -gt 0) {
    # A copied command applies these overrides inside a new child, preserving the caller environment.
    $InnerCommand = ""
    foreach ($Name in @($EnvironmentOverrides.Keys | Sort-Object)) {
      $InnerCommand += '$env:' + $Name + "=" + (Quote-CommandArgument ([string]$EnvironmentOverrides[$Name])) + "; "
    }
    $CommandTokens = @(Quote-CommandArgument $Script)
    foreach ($Argument in $Arguments) {
      if ($Argument -match '^-[A-Za-z][A-Za-z0-9]*$') { $CommandTokens += $Argument }
      else { $CommandTokens += Quote-CommandArgument $Argument }
    }
    $InnerCommand += "& " + ($CommandTokens -join " ") + '; exit $LASTEXITCODE'
    $Tokens = @($script:PowerShellExecutable, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $InnerCommand)
  } else {
    $Tokens = @($script:PowerShellExecutable, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Script) + $Arguments
  }
  return "& " + (($Tokens | ForEach-Object { Quote-CommandArgument $_ }) -join " ")
}
function Show-Usage {
  Write-Host "usage: $(Get-ChildCommand (Join-Path $PSScriptRoot 'tui.ps1')) [-Language zh-CN|en] [-Router <ssh-user>@<router-ip>] [-NoColor] [-Help] [-Version]"
  Write-Host ""
  if ($Language -eq "en") {
    Write-Host @'
Home Edge local help
Help and language switching only change this screen; no router, network, program launch, or project write.

Menu guide:
1. Start or resume: choose a saved session or enter user@router. Diagnosis and planning run before any confirmed change.
   First installation: review compatibility and prerequisites, then the deployment plan. Already installed: inspect diagnosis/session state first; do not assume reinstall or overwrite is required.
2. Diagnosis: run the doctor. Read-only checks may contact a configured router; review reported findings.
3. Session: read saved local state and next-action hints. Saved commands are displayed as data, never executed by this choice.
4. Offline bundle: verify the runtime bundle and readiness before deployment.
5. Support: export a redacted local support bundle; review its contents before sharing.
6 / H / ? / help: show this local help at any time from the main menu.
7. Decommission: show the project removal plan, then require DECOMMISSION before applying it.
8. Desktop: explicitly create or refresh a local launcher; this writes local launcher files.
9 / L / language: toggle Chinese and English immediately for this session, keeping the router and selected session.
R. Explicitly refresh owned project content: review a fresh installation probe and plan, then type REPLACE followed by APPLY. Runtime/core assets are preserved; project-managed policy, integration and configuration may change per plan. The current tree is backed up to <project-path>.prev; an older backup may be replaced.
0. Exit. End of input (EOF) exits; at a confirmation prompt, EOF or any other token cancels that operation. Ctrl+C interrupts.

Safety: review the exact command, target, expected effect, session/log destinations and rollback path before confirming.
Deployment requires exact APPLY; project refresh additionally requires REPLACE first; live self-heal requires exact ENABLE; project removal requires exact DECOMMISSION.
Tokens are case-sensitive and accept no extra spaces. Help/language/Enter do not authorize these operations.
If an operation is unavailable, keep using local help and check compatibility before adding an adapter.

Project location: use the complete cloned or extracted folder containing PROJECT, README.md and scripts; do not select a ZIP or single script.
The paths below bind to this running project. Open/read them yourself; help does not open programs.
'@
  } else {
    Write-Host (Decode-Text "SG9tZSBFZGdlIOacrOWcsOW4ruWKqQrluK7liqnlkozor63oqIDliIfmjaLlj6rmlLnlj5jlvZPliY3nlYzpnaLvvJvkuI3kvJrogZTns7vot6/nlLHlmajjgIHogZTnvZHjgIHmiZPlvIDnqIvluo/miJblhpnlhaXpobnnm67jgIIKCuiPnOWNleivtOaYju+8mgoxLiDlvIDlp4vmiJbmjqXnu63vvJrpgInmi6nlt7LmnInkvJror53miJbovpPlhaUgdXNlckByb3V0ZXLjgILlhYjor4rmlq3lkozlrqHmn6XorqHliJLvvIzlho3noa7orqTkv67mlLnjgIIKICAg6aaW5qyh5a6J6KOF77ya5YWI5qC45a+55YW85a655oCn5LiO5YmN572u5p2h5Lu277yM5YaN5a6h5p+l6YOo572y6K6h5YiS44CC5bey57uP5a6J6KOF77ya5YWI5p+l55yL6K+K5pat5ZKM5Lya6K+d54q25oCB77yb5LiN6KaB6buY6K6k6ZyA6KaB6YeN6KOF5oiW6KaG55uW44CCCjIuIOWPquivu+iviuaWre+8mui/kOihjCBkb2N0b3LjgILlj6ror7vmo4Dmn6Xlj6/og73ogZTns7vlt7LphY3nva7ot6/nlLHlmajvvIzor7flrqHmn6Xlj5HnjrDnmoTpl67popjjgIIKMy4g5Lya6K+d54q25oCB77ya6K+75Y+W5pys5Zyw5L+d5a2Y55qE54q25oCB5ZKM5LiL5LiA5q2l5o+Q56S677yb6K6w5b2V5Lit55qE5ZG95Luk5LuF5L2c5Li65pWw5o2u5bGV56S677yM5q2k6YCJ6aG55LiN5Lya5omn6KGM5a6D5Lus44CCCjQuIOemu+e6vyBidW5kbGXvvJrpg6jnvbLliY3pqozor4Hov5DooYzml7bljIXkuI7lsLHnu6rmg4XlhrXjgIIKNS4g5pSv5oyB5YyF77ya5a+85Ye65pys5Zyw6ISx5pWP5pSv5oyB5YyF77yb5YiG5Lqr5YmN6K+35a6h5p+l5YaF5a6544CCCjYgLyBIIC8gPyAvIGhlbHDvvJrlnKjkuLvoj5zljZXpmo/ml7bmn6XnnIvmraTmnKzlnLDluK7liqnjgIIKNy4g6aG555uu6YCA5Ye677ya5YWI5pi+56S66aG555uu56e76Zmk6K6h5YiS77yM6L6T5YWlIERFQ09NTUlTU0lPTiDlkI7miY3kvJrmiafooYzjgIIKOC4g5qGM6Z2i5YWl5Y+j77ya5piO56Gu5Yib5bu65oiW5pu05paw5pys5py65ZCv5Yqo5YWl5Y+j77yM5Lya5YaZ5YWl5pys5py65ZCv5Yqo5paH5Lu244CCCjkgLyBMIC8gbGFuZ3VhZ2XvvJrnq4vljbPliIfmjaLmnKzmrKHkvJror53nmoTkuK3oi7HmlofvvIzkv53nlZnot6/nlLHlmajlkozmiYDpgInkvJror53jgIIKUi4g5piO56Gu5Yi35paw5bey56Gu6K6k5bGe5LqO5pys6aG555uu55qE6ISa5pys77ya5YWI5a6h5p+l5pyA5paw5a6J6KOF5o6i5rWL5LiO6K6h5YiS77yM5YaN5YWI6L6T5YWlIFJFUExBQ0Ug5ZCO6L6T5YWlIEFQUExZ44CC5L+d55WZ6L+Q6KGM5pe25ZKM5qC45b+D6LWE5Lqn77yb6aG555uu566h55CG55qE562W55Wl44CB6ZuG5oiQ5ZKM6YWN572u5Y+v6IO95oyJ6K6h5YiS5pu05paw77yb5b2T5YmN6aG555uu5qCR5aSH5Lu96IezIDzpobnnm67ot6/lvoQ+LnByZXbvvIzml6flpIfku73lj6/og73ooqvmm7/mjaLjgIIKMC4g6YCA5Ye644CC6L6T5YWl57uT5p2f77yIRU9G77yJ5Lya6YCA5Ye677yb56Gu6K6k5o+Q56S65aSE55qEIEVPRiDmiJblhbbku5bku6TniYzlj5bmtojor6Xmk43kvZzjgIJDdHJsK0Mg5Lit5pat44CCCgrlronlhajnuqbmnZ/vvJrnoa7orqTliY3lrqHmn6Xnsr7noa7lkb3ku6TjgIHnm67moIfjgIHpooTmnJ/lvbHlk43jgIHkvJror53lkozml6Xlv5fkvY3nva7ku6Xlj4rlm57pgIDot6/lvoTjgIIK6YOo572y5b+F6aG757K+56Gu6L6T5YWlIEFQUExZ77yb5Yi35paw5pys6aG555uu6L+Y5b+F6aG75YWI6L6T5YWlIFJFUExBQ0XvvJvnnJ/lrp7oh6rmhIjlv4Xpobvnsr7noa7ovpPlhaUgRU5BQkxF77yb6aG555uu56e76Zmk5b+F6aG757K+56Gu6L6T5YWlIERFQ09NTUlTU0lPTuOAggrku6TniYzljLrliIblpKflsI/lhpnkuJTkuI3mjqXlj5flpJrkvZnnqbrmoLzjgILluK7liqnjgIHliIfmjaLor63oqIDmiJblm57ovabpg73kuI3mjojmnYPov5nkupvmk43kvZzjgIIK5aaC5pON5L2c5bCa5LiN5Y+v55So77yM5Y+v57un57ut5p+l55yL5pys5Zyw5biu5Yqp77yM5bm25Zyo5re75Yqg6YCC6YWN5Zmo5YmN5qC45a+55YW85a655oCn44CCCgrpobnnm67nm67lvZXvvJror7fpgInmi6nlrozmlbTlhYvpmobmiJbop6PljovlkI7nmoTmlofku7blpLnvvIzlhbbkuK3lupTljIXlkKsgUFJPSkVDVOOAgVJFQURNRS5tZCDlkowgc2NyaXB0c++8m+S4jeimgemAieaLqSBaSVAg5oiW5Y2V5Liq6ISa5pys44CCCuS4i+mdoui3r+W+hOe7keWumuW9k+WJjei/kOihjOeahOmhueebruOAguivt+iHquihjOaJk+W8gOaIlumYheivu++8m+W4ruWKqeS4jeS8muaJk+W8gOeoi+W6j+OAggo=")
  }
  Write-Host (Decode-Text "TCAvIExhbmd1YWdlOiBFbmdsaXNoIDwtPiDkuK3mlocgKHRoaXMgc2Vzc2lvbiAvIOS7heW9k+WJjeS8muivnSku")
  Write-Host "project_dir=$Repo"
  $DocsDir = if ($Language -eq "en") { Join-Path $Repo "docs" } else { Join-Path $Repo "docs\zh-CN" }
  Write-Host "readme=$(Join-Path $Repo $(if ($Language -eq 'en') { 'README.md' } else { 'README.zh-CN.md' }))"
  foreach ($Name in @("LAUNCHER.md", "COMPATIBILITY.md", "RUNBOOK.md", "NO_WALL_BOOTSTRAP.md")) {
    Write-Host "doc=$(Join-Path $DocsDir $Name)"
  }
}
function Switch-Language {
  $script:Language = if ($Language -eq "en") { "zh-CN" } else { "en" }
  Write-Host "language=$Language"
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

try {
  . (Join-Path $PSScriptRoot "lib\project-location.ps1")
  . (Join-Path $PSScriptRoot "lib\host-launcher.ps1")
} catch {
  Write-Host "startup_state=failed"
  Write-Host "project_location_state=invalid"
  Write-Host $_.Exception.Message
  exit 2
}

function Test-Startup {
  try {
    [void](Resolve-HomeEdgeProject $Repo)
    $script:ProjectIdentity = Get-HomeEdgeDirectoryIdentity $Repo
  } catch {
    Write-Host "startup_state=failed"
    Write-Host "project_location_state=invalid"
    Write-Host $_.Exception.Message
    return $false
  }
  if (-not (Get-Command $script:PowerShellExecutable -ErrorAction SilentlyContinue)) {
    Write-Host "startup_state=failed"
    Write-Host "missing_prerequisite=powershell"
    return $false
  }
  return $true
}
if (-not (Test-Startup)) { exit 2 }

function Test-CurrentProject {
  try {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "lib\host-launcher.ps1") -PathType Leaf)) { throw "Missing scripts/lib/host-launcher.ps1." }
    [void](Resolve-HomeEdgeProject $Repo)
    if ((Get-HomeEdgeDirectoryIdentity $Repo) -cne $script:ProjectIdentity) { throw "The project directory was replaced after this guide started." }
    return $true
  } catch {
    $script:LastActionStatus = 2
    Write-Host "condition_state=project_degraded"
    Write-Host $_.Exception.Message
    Write-Host "repair_hint=Restore the complete original project folder and restart this guide from that folder."
    return $false
  }
}

$Zh = @{
  Title = Decode-Text "IyBIb21lIEVkZ2Ug5byV5a+85Zmo"
  Start = Decode-Text "MS4g5byA5aeL5oiW5o6l57ut5byV5a+85byP6YWN572u"
  Doctor = Decode-Text "Mi4g6L+Q6KGM5Y+q6K+76K+K5pat"
  Session = Decode-Text "My4g5p+l55yL5b2T5YmNIGJvb3RzdHJhcCDkvJror53nirbmgIE="
  Bundle = Decode-Text "NC4g6aqM6K+B56a757q/6L+Q6KGM5pe2IGJ1bmRsZQ=="
  Support = Decode-Text "NS4g5a+85Ye66ISx5pWP5pSv5oyB5YyF"
  Help = Decode-Text "Ni4g5p+l55yL5biu5Yqp5LiO5a6J5YWo6L6555WMIFtIIC8gPyAvIGhlbHBd"
  Decommission = Decode-Text "Ny4g5a6h5p+l6aG555uu6YCA5Ye677yI56e76Zmk6aG555uu5Y+X566h5YaF5a6577yM6ZyAIERFQ09NTUlTU0lPTu+8iQ=="
  Exit = Decode-Text "MC4g5LiN5YGa5L+u5pS55bm26YCA5Ye6"
  Prompt = Decode-Text "U2VsZWN0IC8g6K+36YCJ5oupICgwLTksIEw6IExhbmd1YWdlIC8g6K+t6KiALCBIOiBIZWxwIC8g5biu5YqpLCBSKTog"
  Language = Decode-Text "6K+t6KiA"
  Chinese = Decode-Text "5Lit5paH"
  Current = Decode-Text "5b2T5YmN"
  Invalid = Decode-Text "5peg5pWI6YCJ5oup44CC"
  RouterPrompt = Decode-Text "6K+36L6T5YWl6Lev55Sx5ZmoIFNTSCDnm67moIfvvIh1c2VyQGlw77yJOiA="
  RouterInvalid = Decode-Text "6Lev55Sx5Zmo55uu5qCH5qC85byP5peg5pWI44CC"
  ApplyPrompt = Decode-Text "5Y2z5bCG5omn6KGM6YOo572y44CC6L6T5YWlIEFQUExZIOehruiupO+8jOWFtuS7lui+k+WFpeWPlua2iDog"
  EnablePrompt = Decode-Text "5Y2z5bCG5byA5ZCv55yf5a6e6Ieq5oSI44CC6L6T5YWlIEVOQUJMRSDnoa7orqTvvIzlhbbku5bovpPlhaXlj5bmtog6IA=="
  Cancelled = Decode-Text "5pON5L2c5bey5Y+W5raI44CC"
  Safety = Decode-Text "5biu5Yqp5LiO5a6J5YWo6L6555WM77ya5Y+q6K+75pON5L2c5Y+v55u05o6l6L+Q6KGM77yb6YOo572y5ZKM55yf5a6e6Ieq5oSI5b+F6aG76L6T5YWl56Gu6K6k5Luk54mM44CC"
}

$Zh.Desktop = Decode-Text "OC4g5Yib5bu65oiW5pu05paw5pys5py65qGM6Z2i5ZCv5Yqo5YWl5Y+j"
function Show-Menu {
  if ($Language -eq "en") {
    Write-Host "# Home Edge Guide"
    Write-Host "1. Start or resume guided bootstrap"
    Write-Host "2. Run read-only diagnosis"
    Write-Host "3. View current bootstrap session state"
    Write-Host "4. Verify offline runtime bundle"
    Write-Host "5. Export a redacted support bundle"
    Write-Host "6. Show help and safety boundaries [H / ? / help]"
    Write-Host "7. Review project decommission (removes project-managed content; requires DECOMMISSION)"
    Write-Host "8. Create or refresh a local desktop launcher"
  } else {
    foreach ($Key in @("Title", "Start", "Doctor", "Session", "Bundle", "Support", "Help", "Decommission", "Desktop")) { Write-Host $Zh[$Key] }
  }
  $CurrentLanguage = if ($Language -eq "en") { "English" } else { $Zh.Chinese }
  Write-Host ("9. Language / {0} (English / {1}; current / {2}: {3}) [L / language]" -f $Zh.Language, $Zh.Chinese, $Zh.Current, $CurrentLanguage)
  Write-Host ""
  Write-Host (Decode-Text "RGFuZ2Vyb3VzIGNoYW5nZXMgLyDljbHpmanlj5jmm7QgKDcgLyBSKTo=")
  if ($Language -eq "en") {
    Write-Host "  7 removes project-managed content; R can update policy, integration and configuration, and replace an older project backup."
    Write-Host "R. Reinstall / refresh this project only (replaces project content; requires REPLACE then APPLY)"
    Write-Host "Local project located; router installation is checked only after choosing a target and an operation."
    Write-Host "0. Exit without changes"
  } else {
    Write-Host (Decode-Text "ICA3IOaMieiuoeWIkuenu+mZpOmhueebruWPl+euoeWGheWuue+8m1Ig5Y+v5pu05paw562W55Wl44CB6ZuG5oiQ5LiO6YWN572u77yM5bm25pu/5o2i5pen55qE6aG555uu5aSH5Lu944CC")
    Write-Host (Decode-Text "Ui4g6YeN5paw5a6J6KOFIC8g5Yi35paw5pys6aG555uu77yI5pu/5o2i6aG555uu5YaF5a6577yM6ZyAIFJFUExBQ0Ug5YaNIEFQUExZ77yJ")
    Write-Host (Decode-Text "5bey5a6a5L2N5pys5Zyw6aG555uu77yb6Lev55Sx5Zmo5a6J6KOF54q25oCB6ZyA6YCJ5oup55uu5qCH5ZKM5pON5L2c5ZCO5omN5qOA5p+l44CC")
    Write-Host $Zh.Exit
  }
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

function Test-OperationAvailable([string]$Script) {
  if (-not (Test-CurrentProject)) { return $false }
  if (-not (Get-Command $script:PowerShellExecutable -ErrorAction SilentlyContinue)) {
    $script:LastActionStatus = 2
    Write-Host "capability_state=unavailable"
    Write-Host "missing_prerequisite=powershell"
    Write-Host "Restore the PowerShell executable, then retry."
    return $false
  }
  if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) {
    $script:LastActionStatus = 2
    Write-Host "capability_state=unavailable"
    Write-Host "missing_component=$([IO.Path]::GetFileName($Script))"
    Write-Host "Restore or update the complete project folder, then restart this guide. Local help, language switching and exit remain available."
    return $false
  }
  return $true
}
function Invoke-ChildScript {
  param([string]$Action, [bool]$WriteStarted, [string]$Script, [string[]]$Arguments = @(), [hashtable]$EnvironmentOverrides = @{})
  if (-not (Test-OperationAvailable $Script)) { return [pscustomobject]@{Status=2;Output="capability_state=unavailable"} }
  $SafeResumeCommand = Get-ChildCommand $Script $Arguments $EnvironmentOverrides
  $Lines = [Collections.Generic.List[string]]::new()
  $PowerShellArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Script) + $Arguments
  $SavedEnvironment = @{}
  try {
    foreach ($Name in $EnvironmentOverrides.Keys) {
      $SavedEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
      [Environment]::SetEnvironmentVariable($Name, [string]$EnvironmentOverrides[$Name], "Process")
    }
    & $script:PowerShellExecutable @PowerShellArguments 2>&1 | ForEach-Object { $Text = [string]$_; $Lines.Add($Text); Write-Host $Text }
    $Status = $LASTEXITCODE
  } finally {
    foreach ($Name in $SavedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($Name, $SavedEnvironment[$Name], "Process") }
  }
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
  if ($script:Router) { $Arguments += @("-Router", $script:Router) }
  return Invoke-ChildScript -Action "doctor" -WriteStarted $false -Script (Join-Path $PSScriptRoot "doctor.ps1") -Arguments $Arguments
}
function Get-BootstrapArguments([string]$Flag = "") {
  $Arguments = @("-NoPause")
  if ($Flag) { $Arguments += $Flag }
  if ($script:SelectedSessionDir) { $Arguments += @("-SessionDir", $script:SelectedSessionDir) }
  $Arguments += @("-Router", $script:Router)
  return $Arguments
}
function Get-ProjectOnlyEnvironment {
  return @{ BOOTSTRAP_INSTALL_RUNTIME="0"; BOOTSTRAP_REPLACE_RUNTIME="0"; BOOTSTRAP_REPLACE_CORE="0"; INCLUDE_BUNDLE="0"; BOOTSTRAP_REPLACE_PROJECT="0"; BOOTSTRAP_PROJECT_CONFIRMATION="" }
}
function Get-BootstrapCommand([string]$Flag = "") {
  return Get-ChildCommand (Join-Path $PSScriptRoot "run-bootstrap.ps1") (Get-BootstrapArguments $Flag) (Get-ProjectOnlyEnvironment)
}
function Invoke-Bootstrap([string]$Action, [string]$Flag = "", [bool]$WriteStarted = $false) {
  return Invoke-ChildScript -Action $Action -WriteStarted $WriteStarted -Script (Join-Path $PSScriptRoot "run-bootstrap.ps1") -Arguments (Get-BootstrapArguments $Flag) -EnvironmentOverrides (Get-ProjectOnlyEnvironment)
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
  Write-Host "rollback_path=$(Get-ChildCommand (Join-Path $PSScriptRoot 'rollback-merlin.ps1') @('-Router', $script:Router))"
  Write-Host "session_destination=$SessionDestination"
  Write-Host "log_destination=$LogDestination"
}

function Get-ProjectInstallation {
  $Probe = Invoke-ChildScript -Action "project_installation_probe" -WriteStarted $false -Script (Join-Path $PSScriptRoot "check-project-installation.ps1") -Arguments @("-Router", $script:Router)
  if ($Probe.Status -ne 0) { Write-Host "attention_state=project_installation_unknown"; return $null }
  $Values = @{}
  foreach ($Name in @("schema", "router", "state", "reason", "path", "replace_allowed")) {
    $MatchesForKey = [regex]::Matches($Probe.Output, "(?m)^project_install_$Name=([^`r`n]*)`r?$")
    if ($MatchesForKey.Count -ne 1) { $script:LastActionStatus = 2; Write-Host "attention_state=invalid_installation_probe"; return $null }
    $Values[$Name] = $MatchesForKey[0].Groups[1].Value
  }
  if ($Values.schema -cne "1" -or $Values.router -cne $script:Router -or $Values.state -cnotin @("installed", "not_installed", "partial", "unknown") -or $Values.reason -cnotmatch '^[a-z0-9_]+$' -or $Values.path -cnotmatch '^/jffs/[A-Za-z0-9_.-]+$' -or (Split-Path -Leaf $Values.path) -in @(".", "..") -or $Values.replace_allowed -notin @("0", "1") -or ($Values.state -in @("unknown", "not_installed") -and $Values.replace_allowed -ne "0")) {
    $script:LastActionStatus = 2; Write-Host "attention_state=invalid_installation_probe"; return $null
  }
  if ($Values.state -eq "unknown") { $script:LastActionStatus = 1; Write-Host "attention_state=project_installation_unknown"; return $null }
  return [pscustomobject]$Values
}
function Show-ExistingInstallation {
  if ($Language -eq "en") { Write-Host "Existing or partial project content was found. Continue with diagnosis and saved session state. To refresh owned project content, explicitly choose R; runtime/core assets are preserved, while project-managed policy, integration and configuration may change per plan." }
  else { Write-Host (Decode-Text "5Y+R546w5bey5pyJ5oiW5LiN5a6M5pW055qE6aG555uu5YaF5a6544CC6buY6K6k57un57ut6K+K5pat5bm25p+l55yL5Lya6K+d54q25oCB77yb5aaC6ZyA5Yi35paw5pys6aG555uu5YaF5a6577yM6K+35piO56Gu6YCJ5oupIFLjgILov5DooYzml7Yv5qC45b+D6LWE5Lqn5L+d55WZ77yb5pys6aG555uu566h55CG55qE562W55Wl44CB6ZuG5oiQ5LiO6YWN572u5Y+v6IO95oyJ6K6h5YiS5Y+Y5YyW44CC") }
}
function Confirm-ProjectRefresh([string]$RemotePath) {
  Write-Host "project_refresh_path=$RemotePath"
  Write-Host "project_backup_path=${RemotePath}.prev"
  if ($Language -eq "en") {
    Write-Host "Refresh replaces this project's managed content. The current project tree is backed up at the path above; an older .prev backup may be replaced. Runtime/core assets are preserved; project-managed policy, integration and configuration may change per plan. Review the plan and backup contents."
    [Console]::Write("Type REPLACE to choose this project refresh; anything else cancels: ")
  } else {
    Write-Host (Decode-Text "5Yi35paw5Lya5pu/5o2i5pys6aG555uu566h55CG55qE5YaF5a6544CC5b2T5YmN6aG555uu5qCR5aSH5Lu96Iez5LiK6L+w6Lev5b6E77yM5penIC5wcmV2IOWkh+S7veWPr+iDveiiq+abv+aNouOAgui/kOihjOaXti/moLjlv4PotYTkuqfkv53nlZnvvJvmnKzpobnnm67nrqHnkIbnmoTnrZbnlaXjgIHpm4bmiJDkuI7phY3nva7lj6/og73mjInorqHliJLlj5jljJbjgILor7flrqHmn6XorqHliJLkuI7lpIfku73lhoXlrrnjgII=")
    [Console]::Write((Decode-Text "6L6T5YWlIFJFUExBQ0Ug5piO56Gu6YCJ5oup5Yi35paw5pys6aG555uu77yM5YW25LuW6L6T5YWl5Y+W5raIOiA="))
  }
  $Confirmation = [Console]::In.ReadLine()
  if ($Confirmation -cne "REPLACE") { if ($Language -eq "en") { Write-Host "Action cancelled." } else { Write-Host $Zh.Cancelled }; return $false }
  if ($Language -eq "en") { [Console]::Write("Type APPLY to apply the reviewed project refresh; anything else cancels: ") }
  else { [Console]::Write($Zh.ApplyPrompt) }
  $Confirmation = [Console]::In.ReadLine()
  if ($Confirmation -cne "APPLY") { if ($Language -eq "en") { Write-Host "Action cancelled." } else { Write-Host $Zh.Cancelled }; return $false }
  return $true
}
function Refresh-Project {
  $script:LastActionStatus = 0
  $DeployScript = Join-Path $PSScriptRoot "deploy-merlin.ps1"
  if (-not (Test-OperationAvailable $DeployScript) -or -not (Test-OperationAvailable (Join-Path $PSScriptRoot "check-project-installation.ps1"))) { return }
  if (-not (Ensure-Router)) { return }
  $Installation = Get-ProjectInstallation
  if ($null -eq $Installation) { return }
  if ($Installation.state -eq "not_installed") {
    if ($Language -eq "en") { Write-Host "Project is not installed on this target. Choose 1 for first installation." }
    else { Write-Host (Decode-Text "5q2k55uu5qCH5bCa5pyq5a6J6KOF5pys6aG555uu44CC6K+36YCJ5oupIDEg6L+b6KGM6aaW5qyh5a6J6KOF44CC") }
    return
  }
  if ($Installation.replace_allowed -ne "1") { Write-Host "attention_state=project_refresh_not_allowed"; return }
  $Scope = Get-ProjectOnlyEnvironment
  $PlanArguments = @("-ProjectOnly", "-Router", $script:Router, "-RemoteDir", $Installation.path)
  $Plan = Invoke-ChildScript -Action "project_refresh_plan" -WriteStarted $false -Script $DeployScript -Arguments $PlanArguments -EnvironmentOverrides $Scope
  if ($Plan.Status -ne 0) { return }
  if ((Get-OutputValue $Plan.Output "deploy_state") -ne "plan" -or (Get-OutputValue $Plan.Output "router") -cne $script:Router -or (Get-OutputValue $Plan.Output "remote_dir") -cne $Installation.path -or (Get-OutputValue $Plan.Output "runtime_assets_effect") -cne "preserve" -or (Get-OutputValue $Plan.Output "integration_effect") -cne "project_managed_configuration_may_change") { Write-Host "attention_state=invalid_project_refresh_plan"; return }
  $ApplyArguments = $PlanArguments + @("-Apply", "-ReplaceProject", "-ProjectConfirmation", "REPLACE")
  Show-WriteDisclosure "refresh_project_managed_content_preserve_runtime_core_assets" (Get-ChildCommand $DeployScript $ApplyArguments $Scope) $Plan.Output
  Write-Host "environment_overrides=BOOTSTRAP_INSTALL_RUNTIME=0 BOOTSTRAP_REPLACE_RUNTIME=0 BOOTSTRAP_REPLACE_CORE=0 INCLUDE_BUNDLE=0"
  if (-not (Confirm-ProjectRefresh $Installation.path)) { return }
  $CurrentInstallation = Get-ProjectInstallation
  if ($null -eq $CurrentInstallation) { return }
  if ($CurrentInstallation.router -cne $Installation.router -or $CurrentInstallation.path -cne $Installation.path -or $CurrentInstallation.state -cne $Installation.state -or $CurrentInstallation.replace_allowed -ne "1") { Write-Host "attention_state=installation_probe_changed"; return }
  $ApplyResult = Invoke-ChildScript -Action "project_refresh_apply" -WriteStarted $true -Script $DeployScript -Arguments $ApplyArguments -EnvironmentOverrides $Scope
  if ($ApplyResult.Status -ne 0) { return }
  if ((Get-OutputValue $ApplyResult.Output "deploy_state") -cne "applied") { $script:LastActionStatus = 2; Write-Host "attention_state=project_refresh_result_unconfirmed"; Write-Host "health_state=not_checked"; return }
  Write-Host "project_refresh_state=applied"
  $DoctorResult = Invoke-Doctor
  if ($DoctorResult.Status -eq 0) { Write-Host "health_state=doctor_reported" }
  else { Write-Host "health_state=not_checked" }
}

function Start-OrResume {
  $script:LastActionStatus = 0
  if (-not (Test-OperationAvailable (Join-Path $PSScriptRoot 'run-bootstrap.ps1'))) { return }
  if (-not (Test-OperationAvailable (Join-Path $PSScriptRoot 'doctor.ps1'))) { return }
  if (-not (Ensure-Router)) { return }
  $Installation = Get-ProjectInstallation
  if ($null -eq $Installation) { return }
  if ($Installation.state -ne "not_installed") { Show-ExistingInstallation }
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
      if ($Installation.state -ne "not_installed") { Show-ExistingInstallation; return }
      $Exact = Get-BootstrapCommand "-ApplyDeploy"
      Show-WriteDisclosure "apply_reviewed_deployment_plan" $Exact $BootstrapResult.Output
      if ($Language -eq "en") { [Console]::Write("Deployment is ready. Type APPLY to confirm; anything else cancels: ") } else { [Console]::Write($Zh.ApplyPrompt) }
      $Confirmation = [Console]::In.ReadLine()
      if ($Confirmation -cne "APPLY") { if ($Language -eq "en") { Write-Host "Action cancelled." } else { Write-Host $Zh.Cancelled }; return }
      [void](Invoke-Bootstrap -Action "apply_deploy" -Flag "-ApplyDeploy" -WriteStarted $true)
    }
    "enable_live_self_heal" {
      if ($Installation.state -eq "partial" -or ($Installation.state -eq "installed" -and $Installation.replace_allowed -ne "1")) { Write-Host "attention_state=installation_requires_review"; return }
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
function Verify-OfflineBundle { [void](Invoke-ChildScript -Action "verify_offline_bundle" -WriteStarted $false -Script (Join-Path $PSScriptRoot "check-no-wall-readiness.ps1")) }
function Export-SupportBundle {
  $Arguments = @()
  if ($script:Router) { $Arguments += @("-Router", $script:Router) }
  [void](Invoke-ChildScript -Action "export_support_bundle" -WriteStarted $false -Script (Join-Path $PSScriptRoot "export-support-bundle.ps1") -Arguments $Arguments)
}
function Show-SafetyHelp { Show-Usage }
function Review-Decommission {
  $script:LastActionStatus = 0
  $Wrapper = Join-Path $PSScriptRoot "decommission-merlin.ps1"
  if (-not (Test-OperationAvailable $Wrapper)) { return }
  if (-not (Ensure-Router)) { return }
  $PlanArguments = @("-NoPause", "-Router", $script:Router)
  $PlanResult = Invoke-ChildScript -Action "decommission_plan" -WriteStarted $false -Script $Wrapper -Arguments $PlanArguments
  if ($PlanResult.Status -ne 0) { return }
  $ApplyArguments = @("-NoPause", "-Apply", "-Confirmation", "DECOMMISSION", "-Router", $script:Router)
  Write-Host "exact_command=$(Get-ChildCommand $Wrapper $ApplyArguments)"
  Write-Host "expected_effect=apply_reviewed_decommission_plan"
  if ($Language -eq "en") {
    [Console]::Write("The project decommission plan is shown above. Type DECOMMISSION to confirm; anything else cancels: ")
  }
  else {
    [Console]::Write((Decode-Text "6aG555uu6YCA5Ye66K6h5YiS5bey5pi+56S644CC6L6T5YWlIERFQ09NTUlTU0lPTiDnoa7orqTvvIzlhbbku5bovpPlhaXlj5bmtog6IA=="))
  }
  $Confirmation = [Console]::In.ReadLine()
  if ($Confirmation -cne "DECOMMISSION") {
    if ($Language -eq "en") { Write-Host "Action cancelled." } else { Write-Host $Zh.Cancelled }
    return
  }
  [void](Invoke-ChildScript -Action "decommission_apply" -WriteStarted $true -Script $Wrapper -Arguments $ApplyArguments)
}

try {
  [Console]::CancelKeyPress += { param($Sender, $EventArgs); $EventArgs.Cancel = $true; $script:Interrupted = $true }
}
catch { }

while ($true) {
  if ($script:Interrupted) { exit 130 }
  $ProjectReady = Test-CurrentProject
  $Prompt = Show-Menu
  [Console]::Write($Prompt)
  $Choice = [Console]::In.ReadLine()
  if ($null -eq $Choice -or $Choice -eq "0") { exit $script:LastActionStatus }
  if ($Choice -notin @("6", "H", "?", "help", "9", "L", "language") -and (-not $ProjectReady -or -not (Test-CurrentProject))) { continue }
  switch ($Choice) {
    "1" { Start-OrResume }
    "R" { Refresh-Project }
    "2" { [void](Invoke-Doctor) }
    "3" { Show-SessionState }
    "4" { Verify-OfflineBundle }
    "5" { Export-SupportBundle }
    { $_ -in @("6", "H", "?", "help") } { Show-SafetyHelp }
    { $_ -in @("9", "L", "language") } { Switch-Language }
    "7" { Review-Decommission }
    "8" { [void](Invoke-ChildScript -Action "create_local_launcher" -WriteStarted $true -Script (Join-Path $PSScriptRoot "create-desktop-shortcut.ps1")) }
    default { if ($Language -eq "en") { Write-Host "Invalid selection." } else { Write-Host $Zh.Invalid } }
  }
  if ($script:Interrupted) { exit 130 }
  Write-Host ""
}
