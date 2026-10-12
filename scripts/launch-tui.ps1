param(
  [string]$Repo = "",
  [string]$Language = "",
  [string]$Router = "",
  [switch]$NoColor,
  [switch]$Help,
  [switch]$Version
)
# home-edge-bootstrap/registered-launcher/v1
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
function Stop-MissingStartupComponent([string]$Relative) {
  Write-Host 'startup_state=failed'
  Write-Host ("missing_component=" + $Relative)
  Write-Host '请恢复完整项目；若注册入口损坏，请从完整项目目录运行 start.cmd，再明确修复注册入口。'
  Write-Host 'Restore the complete project. If its registered entry is damaged, run start.cmd from the complete project folder and explicitly repair the registration.'
  exit 2
}
foreach ($RequiredComponent in @('lib/project-location.ps1', 'lib/ui-language.ps1')) {
  if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $RequiredComponent) -PathType Leaf)) { Stop-MissingStartupComponent $RequiredComponent }
}
. (Join-Path $PSScriptRoot "lib\project-location.ps1")
. (Join-Path $PSScriptRoot "lib\ui-language.ps1")
function Text([string]$Chinese, [string]$English) { Get-HomeEdgeUiText -Language $Language -Chinese $Chinese -English $English }
$DefaultLanguage = Resolve-HomeEdgeUiLanguage
if ($PSBoundParameters.ContainsKey('Language') -and $Language -cnotin @('zh-CN', 'en')) {
  $Language = $DefaultLanguage
  Write-Host (Text '语言无效；请使用 -Language zh-CN 或 -Language en。' 'Invalid language; use -Language zh-CN or -Language en.')
  exit 2
}
$Language = Resolve-HomeEdgeUiLanguage -ExplicitLanguage $Language
$TargetFile = Join-Path $PSScriptRoot "target.txt"
$Registered = (Test-Path -LiteralPath (Join-Path $PSScriptRoot ".home-edge-launcher-owned"))
if ($Help) {
  Write-Host "usage: start.cmd [-Language zh-CN|en] [-Router user@host] [-NoColor] [-Help] [-Version]"
  Write-Host "registered entry: home-edge.cmd [-Repo <complete-project-folder>] [guide options]"
  Write-Host (Text '本地入口会定位自身项目；注册入口会验证保存目录，目录移动后重新请求选择。' 'Local entries resolve their own project. Registered entries validate the saved folder and ask again if it moved.')
  Write-Host (Text '语言顺序：显式 -Language、HOME_EDGE_LANGUAGE、系统界面语言；未设置时使用中文。帮助不会联系路由器或写入项目。' 'Language priority: explicit -Language, HOME_EDGE_LANGUAGE, host UI culture; Chinese when unset. Help does not contact routers or write the project.')
  exit 0
}
try {
  $LauncherLock = $null
  if ($Registered) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'lib/host-launcher.ps1') -PathType Leaf)) { Stop-MissingStartupComponent 'lib/host-launcher.ps1' }
    . (Join-Path $PSScriptRoot "lib\host-launcher.ps1")
  }
  if ($Registered) { $LauncherLock = Enter-HomeEdgeLauncherLock $PSScriptRoot }
  try {
  if ($Registered) { Assert-HomeEdgeRegistrationPaths $PSScriptRoot }
  if ($Registered -and [IO.File]::ReadAllText((Join-Path $PSScriptRoot ".home-edge-launcher-owned")).Trim() -cne "home-edge-bootstrap/registered-launcher/v1") {
    throw (Text '启动器所有权标记无效；未执行项目。请核对入口或从完整项目目录修复。' 'Invalid launcher ownership marker; no project was executed. Check the entry or repair it from the complete project folder.')
  }
  if ($Repo) { $Candidate = $Repo } else {
    $Candidate = if ($Registered -and (Test-Path -LiteralPath $TargetFile)) {
      $Lines = [IO.File]::ReadAllLines($TargetFile, [Text.Encoding]::UTF8)
      if ($Lines.Count -ne 3 -or $Lines[0] -cne "home-edge-bootstrap/target/v2") {
        Write-Host (Text '保存的目录记录无效；请选择完整项目文件夹修复。' 'Invalid saved location; select a complete project folder to repair it.')
        ""
      } else { $SavedIdentity = $Lines[2]; $Lines[1] }
    } else { Join-Path $PSScriptRoot ".." }
  }
  $SelectedAgain = $false
  while ($true) {
    try {
      $Resolved = Resolve-HomeEdgeProject $Candidate
      if ($Registered) {
        $CurrentIdentity = Get-HomeEdgeDirectoryIdentity $Resolved
        if (-not $Repo -and -not $SelectedAgain -and $CurrentIdentity -cne $SavedIdentity) {
          Write-Host (Text '保存的路径已指向另一个目录实例；执行前需要明确重新选择。' 'The saved location now contains a different directory instance. Choose explicitly before executing it.')
          throw 'project_location_state=different_directory_instance'
        }
      }
      break
    }
    catch {
      Write-Host "project_location_state=needs_selection"
      if ($Language -eq 'en') { Write-Host $_.Exception.Message }
      else { Write-Host ("project_location_detail=" + $_.Exception.Message) }
      Write-Host (Text '请选择完整克隆或解压的项目文件夹（包含 PROJECT 和 scripts）；粘贴完整路径，按回车取消。' 'Choose the complete cloned or extracted project folder (containing PROJECT and scripts); paste its full path, or press Enter to cancel.')
      $Selected = $null
      $PickerUsed = $false
      if (-not [Console]::IsInputRedirected) {
        try {
          Add-Type -AssemblyName System.Windows.Forms
          $Picker = New-Object Windows.Forms.FolderBrowserDialog
          $Picker.Description = Text '选择包含 PROJECT 和 scripts 的 Home Edge Bootstrap 文件夹' 'Select the Home Edge Bootstrap folder containing PROJECT and scripts'
          $Picker.ShowNewFolderButton = $false
          try {
            $PickerUsed = $true
            if ($Picker.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $Selected = $Picker.SelectedPath }
          } finally { $Picker.Dispose() }
        } catch { $PickerUsed = $false; Write-Host (Text '文件夹选择器不可用；请在当前窗口粘贴路径。' 'Folder picker unavailable; paste the path in this window.') }
      }
      if (-not $PickerUsed) { $Selected = [Console]::In.ReadLine() }
      if (-not $Selected) { Write-Host (Text '输入为空或结束，启动已取消；未执行项目。' 'Input was empty or ended; startup cancelled; no project was executed.'); exit 2 }
      $Candidate = $Selected
      $SelectedAgain = $true
    }
  }
  if ($SelectedAgain -and $Registered) {
      $OwnedMarker = [IO.File]::ReadAllText((Join-Path $PSScriptRoot ".home-edge-launcher-owned")).Trim()
      if ($OwnedMarker -cne "home-edge-bootstrap/registered-launcher/v1") { throw (Text '启动器所有权标记无效；未修改注册记录。' 'Launcher ownership marker invalid; registration was not changed.') }
      Write-HomeEdgeRegistrationText $TargetFile "home-edge-bootstrap/target/v2`n$Resolved`n$CurrentIdentity`n" ([Text.UTF8Encoding]::new($false))
  }
  } finally { if ($LauncherLock) { Exit-HomeEdgeLauncherLock $LauncherLock } }
  Write-Host "project_location_state=verified_structure"
  Write-Host "project_dir=$Resolved"
  & (Join-Path $Resolved "scripts\tui.ps1") -Language $Language -Router $Router -NoColor:$NoColor -Version:$Version
  exit $LASTEXITCODE
} catch {
  Write-Host "project_location_state=invalid"
  if ($Language -eq 'en') { Write-Host $_.Exception.Message }
  else {
    Write-Host ("launcher_failure_detail=" + $_.Exception.Message)
    Write-Host (Text '启动入口验证失败；请从完整项目目录的 start.cmd 重试，检查入口所有权及注册文件。' 'Startup validation failed; retry start.cmd in the complete project folder and check launcher ownership and registration files.')
  }
  exit 2
}
