param([string]$DestinationDirectory = "", [string]$LauncherDirectory = "", [switch]$ReplaceRegistration, [string]$RegistrationConfirmation = "")

$ErrorActionPreference = "Stop"
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$Launcher = Join-Path $Repo "start.cmd"
$Description = "Home Edge Bootstrap guided TUI"
$RegistrationLock = $null

try {
  . (Join-Path $PSScriptRoot "lib\project-location.ps1")
  . (Join-Path $PSScriptRoot "lib\host-launcher.ps1")
  $Repo = Resolve-HomeEdgeProject $Repo
  $DirectoryIdentity = Get-HomeEdgeDirectoryIdentity $Repo
  if (-not (Test-Path -LiteralPath $Launcher -PathType Leaf) -or
      -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "tui.ps1") -PathType Leaf)) {
    throw "Extract the whole package before creating a shortcut."
  }
  if (-not $DestinationDirectory) {
    $DestinationDirectory = [Environment]::GetFolderPath("DesktopDirectory")
  }
  if (-not $DestinationDirectory -or -not (Test-Path -LiteralPath $DestinationDirectory -PathType Container)) {
    throw "Desktop directory is unavailable. You can still double-click start.cmd."
  }
  $ShortcutPath = Join-Path $DestinationDirectory "Home Edge Bootstrap.lnk"
  Assert-HomeEdgeRegistrationLeaf $ShortcutPath
  $Shell = New-Object -ComObject WScript.Shell
  $Shortcut = $Shell.CreateShortcut($ShortcutPath)
  if (Test-Path -LiteralPath $ShortcutPath) {
    if ($Shortcut.Description -ne $Description -or
        [IO.Path]::GetFileName($Shortcut.TargetPath) -notin @("start.cmd", "home-edge.cmd")) {
      throw "An unrelated desktop shortcut already has this name; it was not changed."
    }
  }
  if (-not $LauncherDirectory) {
    if (-not $env:LOCALAPPDATA) { throw "Local application directory is unavailable." }
    $LauncherDirectory = Join-Path $env:LOCALAPPDATA "HomeEdgeBootstrap\launcher"
  }
  $LauncherDirectory = [IO.Path]::GetFullPath($LauncherDirectory)
  $Marker = Join-Path $LauncherDirectory ".home-edge-launcher-owned"
  Assert-HomeEdgeRegistrationPaths $LauncherDirectory
  if (Test-Path -LiteralPath $LauncherDirectory) {
    $Existing = @(Get-ChildItem -LiteralPath $LauncherDirectory -Force)
    $PartialItems = @($Existing | Where-Object { $_.Name -ne ".home-edge-launcher.lock" })
    $EmptyPartial = $PartialItems.Count -eq 0 -or ($PartialItems.Count -eq 1 -and $PartialItems[0].Name -eq "lib" -and $PartialItems[0].PSIsContainer -and @(Get-ChildItem -LiteralPath $PartialItems[0].FullName -Force).Count -eq 0)
    if ((Test-Path -LiteralPath $Marker) -and [IO.File]::ReadAllText($Marker).Trim() -cne "home-edge-bootstrap/registered-launcher/v1") {
      throw "Launcher directory has another ownership marker; nothing was overwritten."
    }
    if (-not (Test-Path -LiteralPath $Marker) -and -not $EmptyPartial) {
      throw "Launcher directory is not owned by this project; nothing was overwritten."
    }
  }
  New-Item -ItemType Directory -Path $LauncherDirectory -Force | Out-Null
  $RegistrationLock = Enter-HomeEdgeLauncherLock $LauncherDirectory
  Assert-HomeEdgeRegistrationPaths $LauncherDirectory
  Assert-HomeEdgeRegistrationLeaf $ShortcutPath
  $RegistrationState = "not_registered"
  $ExistingProject = ""
  $TargetPath = Join-Path $LauncherDirectory "target.txt"
  if (Test-Path -LiteralPath $Marker) {
    $RegistrationState = "partial"
    if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
      $TargetLines = [IO.File]::ReadAllLines($TargetPath)
      if ($TargetLines.Count -eq 3 -and $TargetLines[0] -ceq "home-edge-bootstrap/target/v2" -and $TargetLines[1] -and $TargetLines[2]) {
        $ExistingProject = $TargetLines[1]
        $RegistrationState = "different_target"
        if ($ExistingProject -ieq $Repo -and $TargetLines[2] -ceq $DirectoryIdentity) { $RegistrationState = "same_target" }
      }
    }
  }
  Write-Host "registration_state=$RegistrationState"
  Write-Host "requested_project=$Repo"
  if ($ExistingProject) { Write-Host "registered_project=$ExistingProject" }
  if ($RegistrationState -eq "same_target" -and -not $ReplaceRegistration -and -not $RegistrationConfirmation -and (Test-Path -LiteralPath $ShortcutPath)) {
    $CacheMatches = $true
    foreach ($Relative in @("launch-tui.ps1", "lib\project-location.ps1", "lib\host-launcher.ps1")) {
      $CachedPath = Join-Path $LauncherDirectory $Relative
      if (-not (Test-Path -LiteralPath $CachedPath -PathType Leaf) -or
          (Get-FileHash -LiteralPath $CachedPath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $Relative) -Algorithm SHA256).Hash) { $CacheMatches = $false; break }
    }
    if ($CacheMatches -and $Shortcut.TargetPath -ieq (Join-Path $LauncherDirectory "home-edge.cmd") -and
        (Test-Path -LiteralPath (Join-Path $LauncherDirectory "home-edge.cmd") -PathType Leaf)) {
      Write-Host "shortcut_state=reused"
      Write-Host "Existing launcher already uses this project; no registration files were replaced."
      exit 0
    }
  }
  if ($RegistrationState -ne "not_registered") {
    Write-Host "This updates this computer's copied launcher and saved project location; it does not reinstall the router."
    if (-not $ReplaceRegistration) {
      [Console]::Write("Existing registration found. Type REPLACE to choose an update; anything else cancels: ")
      if ([Console]::In.ReadLine() -cne "REPLACE") { Write-Host "shortcut_state=cancelled"; exit 0 }
    }
    if (-not $RegistrationConfirmation) {
      [Console]::Write("Confirm the displayed project target. Type APPLY to replace this owned registration: ")
      $RegistrationConfirmation = [Console]::In.ReadLine()
    }
    if ($RegistrationConfirmation -cne "APPLY") { Write-Host "shortcut_state=cancelled"; exit 0 }
  } elseif ($ReplaceRegistration -or $RegistrationConfirmation) {
    throw "Replacement flags require an existing project-owned registration."
  }
  [void](Resolve-HomeEdgeProject $Repo)
  if ((Get-HomeEdgeDirectoryIdentity $Repo) -cne $DirectoryIdentity) {
    throw "The selected project directory changed during confirmation. Restart setup from the intended complete folder."
  }
  New-Item -ItemType Directory -Path (Join-Path $LauncherDirectory "lib") -Force | Out-Null
  Write-HomeEdgeRegistrationText $Marker "home-edge-bootstrap/registered-launcher/v1`n" ([Text.UTF8Encoding]::new($false))
  Copy-HomeEdgeRegistrationFile (Join-Path $PSScriptRoot "launch-tui.ps1") (Join-Path $LauncherDirectory "launch-tui.ps1")
  Copy-HomeEdgeRegistrationFile (Join-Path $PSScriptRoot "lib\project-location.ps1") (Join-Path $LauncherDirectory "lib\project-location.ps1")
  Copy-HomeEdgeRegistrationFile (Join-Path $PSScriptRoot "lib\host-launcher.ps1") (Join-Path $LauncherDirectory "lib\host-launcher.ps1")
  Write-HomeEdgeRegistrationText (Join-Path $LauncherDirectory "target.txt") "home-edge-bootstrap/target/v2`n$Repo`n$DirectoryIdentity`n" ([Text.UTF8Encoding]::new($false))
  $RegisteredEntry = Join-Path $LauncherDirectory "home-edge.cmd"
  $EntryText = @'
@echo off
rem home-edge-bootstrap/registered-launcher/v1
setlocal
set "HomeEdgeShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%HomeEdgeShell%" (
  where.exe pwsh.exe >nul 2>nul
  if errorlevel 1 (
    echo PowerShell is unavailable. Retry after installing PowerShell for this user.
    pause
    exit /b 2
  )
  set "HomeEdgeShell=pwsh.exe"
)
"%HomeEdgeShell%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0launch-tui.ps1" %*
set "HomeEdgeExit=%errorlevel%"
if not "%HomeEdgeExit%"=="0" pause
exit /b %HomeEdgeExit%
'@
  Write-HomeEdgeRegistrationText $RegisteredEntry $EntryText.Replace("`n", "`r`n") ([Text.Encoding]::ASCII)
  $ShortcutTemporary = Join-Path $DestinationDirectory (".home-edge-shortcut-" + [Guid]::NewGuid().ToString("N") + ".lnk")
  try {
    $NewShortcut = $Shell.CreateShortcut($ShortcutTemporary)
    $NewShortcut.TargetPath = $RegisteredEntry
    $NewShortcut.WorkingDirectory = $LauncherDirectory
    $NewShortcut.Description = $Description
    $NewShortcut.Save()
    Publish-HomeEdgeRegistrationFile $ShortcutTemporary $ShortcutPath
  } finally {
    if (Test-Path -LiteralPath $ShortcutTemporary) { Remove-Item -LiteralPath $ShortcutTemporary -Force }
  }
  Exit-HomeEdgeLauncherLock $RegistrationLock
  $RegistrationLock = $null
  Write-Host "shortcut_state=ready"
  Write-Host "Desktop shortcut: $ShortcutPath"
  Write-Host "Registered project: $Repo"
  Write-Host "If you move the project folder, this entry will ask for its new location."
  exit 0
}
catch {
  Write-Host "shortcut_state=failed"
  Write-Host $_.Exception.Message
  Write-Host "You can still use the directory-local start.cmd. Check permissions or choose an empty launcher directory before retrying shortcut setup."
  exit 1
}
finally {
  Exit-HomeEdgeLauncherLock $RegistrationLock
}
