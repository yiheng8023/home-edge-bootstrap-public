param(
  [string]$Language = "",
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
6 / H / ? / help: open the local help menu; choose 5 there for full help.
7. Project maintenance: open refresh/removal choices. Removal requires DECOMMISSION; refresh requires REPLACE then APPLY.
8. Desktop: explicitly create or refresh a local launcher; this writes local launcher files.
9 / L / language: toggle Chinese and English immediately for this session, keeping the router and selected session.
R. Explicitly refresh owned project content: review a fresh installation probe and plan, then type REPLACE followed by APPLY. Runtime/core assets are preserved; project-managed policy, integration and configuration may change per plan. The current tree is backed up to <project-path>.prev; an older backup may be replaced.
0. Back from a submenu; exit from the main menu. End of input (EOF) exits; at a confirmation prompt, EOF or any other token cancels that operation. Ctrl+C interrupts.

Safety: review the exact command, target, expected effect, session/log destinations and rollback path before confirming.
Deployment requires exact APPLY; project refresh additionally requires REPLACE first; live self-heal requires exact ENABLE; project removal requires exact DECOMMISSION.
Tokens are case-sensitive and accept no extra spaces. Help/language/Enter do not authorize these operations.
If an operation is unavailable, keep using local help and check compatibility before adding an adapter.

Project location: use the complete cloned or extracted folder containing PROJECT, README.md and scripts; do not select a ZIP or single script.
The paths below bind to this running project. Open/read them yourself; help does not open programs.
'@
  } else {
    Write-Host (Decode-Text "SG9tZSBFZGdlIOacrOWcsOW4ruWKqQrluK7liqnlkozor63oqIDliIfmjaLlj6rmlLnlj5jlvZPliY3nlYzpnaLvvJvkuI3kvJrogZTns7vot6/nlLHlmajjgIHogZTnvZHjgIHmiZPlvIDnqIvluo/miJblhpnlhaXpobnnm67jgIIKCuiPnOWNleivtOaYju+8mgoxLiDlvIDlp4vmiJbmjqXnu63vvJrpgInmi6nlt7LmnInkvJror53miJbovpPlhaUgdXNlckByb3V0ZXLjgILlhYjor4rmlq3lkozlrqHmn6XorqHliJLvvIzlho3noa7orqTkv67mlLnjgIIKICAg6aaW5qyh5a6J6KOF77ya5YWI5qC45a+55YW85a655oCn5LiO5YmN572u5p2h5Lu277yM5YaN5a6h5p+l6YOo572y6K6h5YiS44CC5bey57uP5a6J6KOF77ya5YWI5p+l55yL6K+K5pat5ZKM5Lya6K+d54q25oCB77yb5LiN6KaB6buY6K6k6ZyA6KaB6YeN6KOF5oiW6KaG55uW44CCCjIuIOWPquivu+iviuaWre+8mui/kOihjCBkb2N0b3LjgILlj6ror7vmo4Dmn6Xlj6/og73ogZTns7vlt7LphY3nva7ot6/nlLHlmajvvIzor7flrqHmn6Xlj5HnjrDnmoTpl67popjjgIIKMy4g5Lya6K+d54q25oCB77ya6K+75Y+W5pys5Zyw5L+d5a2Y55qE54q25oCB5ZKM5LiL5LiA5q2l5o+Q56S677yb6K6w5b2V5Lit55qE5ZG95Luk5LuF5L2c5Li65pWw5o2u5bGV56S677yM5q2k6YCJ6aG55LiN5Lya5omn6KGM5a6D5Lus44CCCjQuIOemu+e6vyBidW5kbGXvvJrpg6jnvbLliY3pqozor4Hov5DooYzml7bljIXkuI7lsLHnu6rmg4XlhrXjgIIKNS4g5pSv5oyB5YyF77ya5a+85Ye65pys5Zyw6ISx5pWP5pSv5oyB5YyF77yb5YiG5Lqr5YmN6K+35a6h5p+l5YaF5a6544CCCjYgLyBIIC8gPyAvIGhlbHDvvJrov5vlhaXmnKzlnLDluK7liqnoj5zljZXvvIzpgInmi6kgNSDmn6XnnIvlrozmlbTluK7liqnjgIIKNy4g6aG555uu57u05oqk77ya6L+b5YWl5Yi35paw5oiW6YCA5Ye65a2Q6I+c5Y2V44CC6YCA5Ye66ZyAIERFQ09NTUlTU0lPTu+8m+WIt+aWsOmcgCBSRVBMQUNFIOWGjSBBUFBMWeOAggo4LiDmoYzpnaLlhaXlj6PvvJrmmI7noa7liJvlu7rmiJbmm7TmlrDmnKzmnLrlkK/liqjlhaXlj6PvvIzkvJrlhpnlhaXmnKzmnLrlkK/liqjmlofku7bjgIIKOSAvIEwgLyBsYW5ndWFnZe+8mueri+WNs+WIh+aNouacrOasoeS8muivneeahOS4reiLseaWh++8jOS/neeVmei3r+eUseWZqOWSjOaJgOmAieS8muivneOAggpSLiDmmI7noa7liLfmlrDlt7Lnoa7orqTlsZ7kuo7mnKzpobnnm67nmoTohJrmnKzvvJrlhYjlrqHmn6XmnIDmlrDlronoo4XmjqLmtYvkuI7orqHliJLvvIzlho3lhYjovpPlhaUgUkVQTEFDRSDlkI7ovpPlhaUgQVBQTFnjgILkv53nlZnov5DooYzml7blkozmoLjlv4PotYTkuqfvvJvpobnnm67nrqHnkIbnmoTnrZbnlaXjgIHpm4bmiJDlkozphY3nva7lj6/og73mjInorqHliJLmm7TmlrDvvJvlvZPliY3pobnnm67moJHlpIfku73oh7MgPOmhueebrui3r+W+hD4ucHJldu+8jOaXp+Wkh+S7veWPr+iDveiiq+abv+aNouOAggowLiDlrZDoj5zljZXov5Tlm57vvIzkuLvoj5zljZXpgIDlh7rjgILovpPlhaXnu5PmnZ/vvIhFT0bvvInkvJrpgIDlh7rvvJvnoa7orqTmj5DnpLrlpITnmoQgRU9GIOaIluWFtuS7luS7pOeJjOWPlua2iOivpeaTjeS9nOOAgkN0cmwrQyDkuK3mlq3jgIIKCuWuieWFqOe6puadn++8muehruiupOWJjeWuoeafpeeyvuehruWRveS7pOOAgeebruagh+OAgemihOacn+W9seWTjeOAgeS8muivneWSjOaXpeW/l+S9jee9ruS7peWPiuWbnumAgOi3r+W+hOOAggrpg6jnvbLlv4Xpobvnsr7noa7ovpPlhaUgQVBQTFnvvJvliLfmlrDmnKzpobnnm67ov5jlv4XpobvlhYjovpPlhaUgUkVQTEFDRe+8m+ecn+WunuiHquaEiOW/hemhu+eyvuehrui+k+WFpSBFTkFCTEXvvJvpobnnm67np7vpmaTlv4Xpobvnsr7noa7ovpPlhaUgREVDT01NSVNTSU9O44CCCuS7pOeJjOWMuuWIhuWkp+Wwj+WGmeS4lOS4jeaOpeWPl+WkmuS9meepuuagvOOAguW4ruWKqeOAgeWIh+aNouivreiogOaIluWbnui9pumDveS4jeaOiOadg+i/meS6m+aTjeS9nOOAggrlpoLmk43kvZzlsJrkuI3lj6/nlKjvvIzlj6/nu6fnu63mn6XnnIvmnKzlnLDluK7liqnvvIzlubblnKjmt7vliqDpgILphY3lmajliY3moLjlr7nlhbzlrrnmgKfjgIIKCumhueebruebruW9le+8muivt+mAieaLqeWujOaVtOWFi+mahuaIluino+WOi+WQjueahOaWh+S7tuWkue+8jOWFtuS4reW6lOWMheWQqyBQUk9KRUNU44CBUkVBRE1FLm1kIOWSjCBzY3JpcHRz77yb5LiN6KaB6YCJ5oupIFpJUCDmiJbljZXkuKrohJrmnKzjgIIK5LiL6Z2i6Lev5b6E57uR5a6a5b2T5YmN6L+Q6KGM55qE6aG555uu44CC6K+36Ieq6KGM5omT5byA5oiW6ZiF6K+777yb5biu5Yqp5LiN5Lya5omT5byA56iL5bqP44CCCg==")
  }
  Write-Host (Decode-Text "TCAvIExhbmd1YWdlOiBFbmdsaXNoIDwtPiDkuK3mlocgKHRoaXMgc2Vzc2lvbiAvIOS7heW9k+WJjeS8muivnSku")
  Show-Documents
}
function Show-Documents {
  Write-Host "project_dir=$Repo"
  $DocsDir = if ($Language -eq "en") { Join-Path $Repo "docs" } else { Join-Path $Repo "docs\zh-CN" }
  $Readme = Join-Path $Repo $(if ($Language -eq 'en') { 'README.md' } else { 'README.zh-CN.md' })
  if (Test-Path -LiteralPath $Readme -PathType Leaf) { Write-Host "readme=$Readme" }
  $Quickstart = Join-Path $Repo $(if ($Language -eq 'en') { 'QUICKSTART.md' } else { 'QUICKSTART.zh-CN.md' })
  if (Test-Path -LiteralPath $Quickstart -PathType Leaf) { Write-Host "doc=$Quickstart" }
  foreach ($Name in @("LAUNCHER.md", "COMPATIBILITY.md", "RUNBOOK.md", "NO_WALL_BOOTSTRAP.md")) {
    $Document = Join-Path $DocsDir $Name
    if (Test-Path -LiteralPath $Document -PathType Leaf) { Write-Host "doc=$Document" }
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

$script:LanguageReady = $true
$LanguageHelper = Join-Path $PSScriptRoot "lib\ui-language.ps1"
if ($PSBoundParameters.ContainsKey('Language') -and -not $Language) { [Console]::Error.WriteLine('unsupported language: empty'); exit 2 }
if (Test-Path -LiteralPath $LanguageHelper -PathType Leaf) {
  try { . $LanguageHelper; $Language = Resolve-HomeEdgeUiLanguage -ExplicitLanguage $Language }
  catch { [Console]::Error.WriteLine($_.Exception.Message); exit 2 }
} else {
  $script:LanguageReady = $false
  if (-not $Language) { $Language = 'zh-CN' }
  if ($Language -cnotin @('zh-CN','en')) { [Console]::Error.WriteLine("unsupported language: $Language"); exit 2 }
  Write-Host 'missing_component=scripts/lib/ui-language.ps1'
  Write-Host 'Restore the complete project folder / 请恢复完整项目目录。'
  function Get-HomeEdgeUiText([string]$Language, [string]$Chinese, [string]$English) { if ($Language -eq 'en') { $English } else { $Chinese } }
}
function Write-UiText([string]$Chinese, [string]$English) { Write-Host (Get-HomeEdgeUiText -Language $Language -Chinese $Chinese -English $English) }
if ($Router -and -not (Test-RouterTarget $Router)) { [Console]::Error.WriteLine("invalid router target: $Router"); exit 2 }
if ($Help) { Show-Usage; exit 0 }
if ($Version) { Show-Version; exit 0 }

$script:StartupReady = $script:LanguageReady
try {
  . (Join-Path $PSScriptRoot "lib\project-location.ps1")
  . (Join-Path $PSScriptRoot "lib\host-launcher.ps1")
} catch {
  Write-Host "startup_state=failed"
  Write-Host "project_location_state=invalid"
  Write-Host "startup_detail=$($_.Exception.Message)"
  Write-UiText "repair_hint=请恢复完整项目目录后重新启动；本地帮助、语言和退出仍可使用。" "repair_hint=Restore the complete project folder and restart. Local help, language and exit remain available."
  $script:StartupReady = $false
}

function Test-Startup {
  try {
    [void](Resolve-HomeEdgeProject $Repo)
    $script:ProjectIdentity = Get-HomeEdgeDirectoryIdentity $Repo
  } catch {
    Write-Host "startup_state=failed"
    Write-Host "project_location_state=invalid"
    Write-Host "startup_detail=$($_.Exception.Message)"
    Write-UiText "repair_hint=请恢复完整项目目录与所需本地工具后重新启动。" "repair_hint=Restore the complete project folder and required local tools, then restart."
    return $false
  }
  if (-not (Get-Command $script:PowerShellExecutable -ErrorAction SilentlyContinue)) {
    Write-Host "startup_state=failed"
    Write-Host "missing_prerequisite=powershell"
    return $false
  }
  return $true
}
if ($script:StartupReady) { $script:StartupReady = Test-Startup }
if (-not $script:StartupReady) { $script:LastActionStatus = 2; Write-UiText "repair_hint=请恢复完整项目目录及所需本地工具后重新启动；本地帮助、语言和退出仍可使用。" "repair_hint=Restore the complete project folder and required local tools, then restart. Local help, language and exit remain available." }

function Test-CurrentProject {
  if (-not $script:StartupReady) { $script:LastActionStatus = 2; return $false }
  try {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "lib\host-launcher.ps1") -PathType Leaf)) { throw "Missing scripts/lib/host-launcher.ps1." }
    [void](Resolve-HomeEdgeProject $Repo)
    if ((Get-HomeEdgeDirectoryIdentity $Repo) -cne $script:ProjectIdentity) { throw "The project directory was replaced after this guide started." }
    return $true
  } catch {
    $script:LastActionStatus = 2
    Write-Host "condition_state=project_degraded"
    Write-Host "condition_detail=$($_.Exception.Message)"
    Write-UiText "repair_hint=项目目录或所需本地工具已变化；请恢复完整的原项目目录并从该目录重新启动。" "repair_hint=The project folder or required local tools changed; restore the complete original folder and restart from it."
    return $false
  }
}

$Zh = @{
  Prompt = Decode-Text "U2VsZWN0IC8g6K+36YCJ5oupICgwLTksIEw6IExhbmd1YWdlIC8g6K+t6KiALCBIOiBIZWxwIC8g5biu5YqpLCBSKTog"
  RouterPrompt = Decode-Text "6K+36L6T5YWl6Lev55Sx5ZmoIFNTSCDnm67moIfvvIh1c2VyQGlw77yJOiA="
  RouterInvalid = Decode-Text "6Lev55Sx5Zmo55uu5qCH5qC85byP5peg5pWI44CC"
  ApplyPrompt = Decode-Text "5Y2z5bCG5omn6KGM6YOo572y44CC6L6T5YWlIEFQUExZIOehruiupO+8jOWFtuS7lui+k+WFpeWPlua2iDog"
  EnablePrompt = Decode-Text "5Y2z5bCG5byA5ZCv55yf5a6e6Ieq5oSI44CC6L6T5YWlIEVOQUJMRSDnoa7orqTvvIzlhbbku5bovpPlhaXlj5bmtog6IA=="
  Cancelled = Decode-Text "5pON5L2c5bey5Y+W5raI44CC"
}

function Show-Menu {
  if ($script:MenuPage -eq "help") {
    Write-UiText "Home Edge 本地帮助 / 帮助菜单" "Home Edge local help / Help menu"
    Write-UiText "1. 入门：首次安装 / 已安装" "1. Getting started: first installation / already installed"
    Write-UiText "2. 安全与确认令牌" "2. Safety and confirmation tokens"
    Write-UiText "3. 故障与恢复" "3. Troubleshooting and recovery"
    Write-UiText "4. 当前项目文档路径" "4. Current project documentation paths"
    Write-UiText "5. 完整帮助" "5. Full help"
  } elseif ($script:MenuPage -eq "maintenance") {
    Write-UiText "Home Edge / 项目维护" "Home Edge / Project maintenance"
    Write-UiText "1. 刷新本项目 [R]：需 REPLACE 再 APPLY，可能更新策略、集成与配置及替换旧备份" "1. Refresh this project [R]: REPLACE then APPLY; may change policy, integration, configuration and replace an older backup"
    Write-UiText "2. 项目退出：需 DECOMMISSION，按计划移除项目受管内容" "2. Decommission: DECOMMISSION removes project-managed content per plan"
  } else {
    Write-UiText "# Home Edge 引导器" "# Home Edge Guide"
    Write-Host ""
    Write-UiText "常用操作" "Common actions"
    Write-UiText "1. 开始或接续引导式配置" "1. Start or resume guided bootstrap"
    Write-UiText "2. 运行只读诊断" "2. Run read-only diagnosis"
    Write-UiText "3. 查看当前 bootstrap 会话状态" "3. View current bootstrap session state"
    Write-Host ""
    Write-UiText "工具与帮助" "Tools and help"
    Write-UiText "4. 验证离线运行时 bundle" "4. Verify offline runtime bundle"
    Write-UiText "5. 导出脱敏支持包" "5. Export a redacted support bundle"
    Write-UiText "6. 帮助 > [H / ? / help]" "6. Help > [H / ? / help]"
    Write-Host ""
    Write-UiText "维护与偏好" "Maintenance and preferences"
    Write-UiText "7. 项目维护 >" "7. Project maintenance >"
    Write-UiText "8. 创建或更新本机桌面启动入口" "8. Create or refresh a local desktop launcher"
  }
  $CurrentLanguage = if ($Language -eq "en") { "English" } else { "中文" }
  Write-Host "9. Language / 语言 (English / 中文; current / 当前: $CurrentLanguage) [L / language]"
  if ($script:MenuPage -eq "main") { Write-UiText "0. 不做修改并退出" "0. Exit without changes" }
  else { Write-UiText "0. 返回上一层" "0. Back" }
  if ($script:MenuPage -eq "main") {
    Write-UiText "R: 刷新本项目快捷键（确认及影响见项目维护）" "R: Project refresh shortcut (confirmations and effects in maintenance)"
    return $Zh.Prompt
  }
  if ($script:MenuPage -eq "help") { return "Select / 请选择 (0-5/9, L: Language / 语言, H: Help / 帮助): " }
  return "Select / 请选择 (0-2/9, L: Language / 语言, H: Help / 帮助, R): "
}
function Show-HelpTopic([string]$Choice) {
  switch ($Choice) {
    "1" { Write-UiText "首次安装：先阅读兼容性与前置条件，再选择主菜单 1，审查诊断和部署计划。已经安装：先查看诊断或会话状态，不要默认重装。" "First installation: read compatibility and prerequisites, then choose main menu 1 and review diagnosis and the deployment plan. Already installed: inspect diagnosis or session state before considering reinstall." }
    "2" { Write-UiText "部署需 APPLY；刷新需 REPLACE 再 APPLY；真实自愈需 ENABLE；项目退出需 DECOMMISSION。令牌区分大小写且不接受多余空格。先审查命令、目标、影响与回退路径。帮助、语言或回车不授权写入。" "Deployment requires APPLY; refresh requires REPLACE then APPLY; live self-heal requires ENABLE; removal requires DECOMMISSION. Tokens are case-sensitive with no extra spaces. Review command, target, effects and rollback. Help, language and Enter do not authorize writes." }
    "3" { Write-UiText "保留错误、会话和日志，先核对完整项目目录与所需本地工具。不要盲目重放写入；先核实实际状态。EOF 退出引导器；确认处 EOF 取消操作。本地帮助、语言和退出保持可用。" "Keep the error, session and logs; check the complete project folder and required local tools. Verify actual state before retrying a write. EOF exits the guide; EOF at confirmation cancels the action. Local help, language and exit remain available." }
    "4" { Show-Documents }
    "5" { Show-Usage }
  }
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
    Write-UiText "repair_hint=请恢复 PowerShell 可执行文件后重试。" "repair_hint=Restore the PowerShell executable, then retry."
    return $false
  }
  if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) {
    $script:LastActionStatus = 2
    Write-Host "capability_state=unavailable"
    Write-Host "missing_component=$([IO.Path]::GetFileName($Script))"
    Write-UiText "repair_hint=请恢复或更新完整项目目录后重新启动。本地帮助、语言切换和退出仍可使用。" "repair_hint=Restore or update the complete project folder, then restart this guide. Local help, language switching and exit remain available."
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
    Write-UiText "repair_hint=请保留错误与日志，核实实际状态后再决定是否重试；可在帮助菜单查看故障恢复。" "repair_hint=Keep the error and logs, verify actual state before retrying; see recovery in Help."
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
  else { [Console]::Write("即将执行已审查的项目刷新。输入 APPLY 确认，其他输入取消: ") }
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

$script:MenuPage = "main"
$script:HelpParentPage = "main"
while ($true) {
  if ($script:Interrupted) { exit 130 }
  $Prompt = Show-Menu
  [Console]::Write($Prompt)
  $Choice = [Console]::In.ReadLine()
  if ($null -eq $Choice) { exit $script:LastActionStatus }
  if ($Choice -eq "") { continue }
  if ($Choice -eq "0") {
    if ($script:MenuPage -eq "main") { exit $script:LastActionStatus }
    $script:MenuPage = if ($script:MenuPage -eq "help") { $script:HelpParentPage } else { "main" }; continue
  }
  if ($Choice -in @("9", "L", "language")) { Switch-Language; continue }
  if ($Choice -in @("H", "?", "help")) { if ($script:MenuPage -ne "help") { $script:HelpParentPage = $script:MenuPage }; $script:MenuPage = "help"; continue }
  if ($script:MenuPage -eq "help") {
    if ($Choice -in @("1","2","3","4","5")) { Show-HelpTopic $Choice }
    else { Write-UiText "无效选择。" "Invalid selection." }
    continue
  }
  if ($script:MenuPage -eq "main") {
    if ($Choice -eq "6") { $script:HelpParentPage = "main"; $script:MenuPage = "help"; continue }
    if ($Choice -eq "7") { $script:MenuPage = "maintenance"; continue }
    if ($Choice -notin @("1","2","3","4","5","8","R")) { Write-UiText "无效选择。" "Invalid selection."; continue }
  } elseif ($Choice -notin @("1","2","R")) { Write-UiText "无效选择。" "Invalid selection."; continue }
  if (-not (Test-CurrentProject)) { continue }
  if ($script:MenuPage -eq "maintenance") {
    if ($Choice -in @("1","R")) { Refresh-Project } else { Review-Decommission }
  } else {
    switch ($Choice) {
      "1" { Start-OrResume }
      "R" { Refresh-Project }
      "2" { [void](Invoke-Doctor) }
      "3" { Show-SessionState }
      "4" { Verify-OfflineBundle }
      "5" { Export-SupportBundle }
      "8" { [void](Invoke-ChildScript -Action "create_local_launcher" -WriteStarted $true -Script (Join-Path $PSScriptRoot "create-desktop-shortcut.ps1")) }
    }
  }
  if ($script:Interrupted) { exit 130 }
  Write-Host ""
}
