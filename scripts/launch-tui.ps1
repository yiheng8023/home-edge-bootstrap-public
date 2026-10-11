param(
  [string]$Repo = "",
  [string]$Language = "zh-CN",
  [string]$Router = "",
  [switch]$NoColor,
  [switch]$Help,
  [switch]$Version
)
# home-edge-bootstrap/registered-launcher/v1
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot "lib\project-location.ps1")
$TargetFile = Join-Path $PSScriptRoot "target.txt"
$Registered = (Test-Path -LiteralPath (Join-Path $PSScriptRoot ".home-edge-launcher-owned"))
if ($Help) {
  Write-Host "usage: start.cmd [-Language zh-CN|en] [-Router user@host] [-NoColor] [-Help] [-Version]"
  Write-Host "registered entry: home-edge.cmd [-Repo <complete-project-folder>] [guide options]"
  Write-Host "Local entries resolve their own project. Registered entries validate the saved folder and ask again if it moved."
  exit 0
}
try {
  $LauncherLock = $null
  if ($Registered) { . (Join-Path $PSScriptRoot "lib\host-launcher.ps1") }
  if ($Registered) { $LauncherLock = Enter-HomeEdgeLauncherLock $PSScriptRoot }
  try {
  if ($Registered) { Assert-HomeEdgeRegistrationPaths $PSScriptRoot }
  if ($Registered -and [IO.File]::ReadAllText((Join-Path $PSScriptRoot ".home-edge-launcher-owned")).Trim() -cne "home-edge-bootstrap/registered-launcher/v1") {
    throw "Invalid launcher ownership marker; no project was executed."
  }
  if ($Repo) { $Candidate = $Repo } else {
    $Candidate = if ($Registered -and (Test-Path -LiteralPath $TargetFile)) {
      $Lines = [IO.File]::ReadAllLines($TargetFile, [Text.Encoding]::UTF8)
      if ($Lines.Count -ne 3 -or $Lines[0] -cne "home-edge-bootstrap/target/v2") {
        Write-Host "Invalid saved location; select a complete project folder to repair it."
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
          throw "The saved location now contains a different directory instance. Choose explicitly before executing it."
        }
      }
      break
    }
    catch {
      Write-Host "project_location_state=needs_selection"
      Write-Host $_.Exception.Message
      Write-Host "Paste the complete project folder path (containing PROJECT and scripts), or press Enter to cancel."
      $Selected = $null
      $PickerUsed = $false
      if (-not [Console]::IsInputRedirected) {
        try {
          Add-Type -AssemblyName System.Windows.Forms
          $Picker = New-Object Windows.Forms.FolderBrowserDialog
          $Picker.Description = "Select the Home Edge Bootstrap folder containing PROJECT and scripts"
          $Picker.ShowNewFolderButton = $false
          try {
            $PickerUsed = $true
            if ($Picker.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $Selected = $Picker.SelectedPath }
          } finally { $Picker.Dispose() }
        } catch { $PickerUsed = $false; Write-Host "Folder picker unavailable; paste the path in this window." }
      }
      if (-not $PickerUsed) { $Selected = [Console]::In.ReadLine() }
      if (-not $Selected) { Write-Host "Startup cancelled; no project was executed."; exit 2 }
      $Candidate = $Selected
      $SelectedAgain = $true
    }
  }
  if ($SelectedAgain -and $Registered) {
      $OwnedMarker = [IO.File]::ReadAllText((Join-Path $PSScriptRoot ".home-edge-launcher-owned")).Trim()
      if ($OwnedMarker -cne "home-edge-bootstrap/registered-launcher/v1") { throw "Launcher ownership marker invalid; registration was not changed." }
      Write-HomeEdgeRegistrationText $TargetFile "home-edge-bootstrap/target/v2`n$Resolved`n$CurrentIdentity`n" ([Text.UTF8Encoding]::new($false))
  }
  } finally { if ($LauncherLock) { Exit-HomeEdgeLauncherLock $LauncherLock } }
  Write-Host "project_location_state=verified_structure"
  Write-Host "project_dir=$Resolved"
  & (Join-Path $Resolved "scripts\tui.ps1") -Language $Language -Router $Router -NoColor:$NoColor -Version:$Version
  exit $LASTEXITCODE
} catch {
  Write-Host "project_location_state=invalid"
  Write-Host $_.Exception.Message
  exit 2
}
