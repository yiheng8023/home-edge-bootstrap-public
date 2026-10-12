param([string]$Repo = "", [switch]$MissingComponentsOnly)
$ErrorActionPreference = "Stop"
if (-not $Repo) { $Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..")) }
$Base = Join-Path ([IO.Path]::GetTempPath()) ("home-edge-launcher-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $Base | Out-Null

function Invoke-Entry([string]$File, [string]$Arguments = "", [string]$InputText = "", [string]$LanguagePreference = "en") {
  $Info = [Diagnostics.ProcessStartInfo]::new()
  if ([IO.Path]::GetExtension($File) -eq ".cmd") {
    $Info.FileName = $env:ComSpec
    $Info.Arguments = '/d /c ""' + $File + '" ' + $Arguments + '"'
  } else {
    $Info.FileName = "powershell.exe"
    $Info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $File + '" ' + $Arguments
  }
  $Info.WorkingDirectory = $Base
  $Info.UseShellExecute = $false
  $Info.EnvironmentVariables['HOME_EDGE_LANGUAGE'] = $LanguagePreference
  $Info.RedirectStandardInput = $true
  $Info.RedirectStandardOutput = $true
  $Info.RedirectStandardError = $true
  $Info.StandardOutputEncoding = [Text.Encoding]::UTF8
  $Process = [Diagnostics.Process]::Start($Info)
  $OutputTask = $Process.StandardOutput.ReadToEndAsync()
  $ErrorTask = $Process.StandardError.ReadToEndAsync()
  $Process.StandardInput.Write($InputText)
  $Process.StandardInput.Close()
  if (-not $Process.WaitForExit(30000)) { $Process.Kill(); throw "Launcher fixture timed out" }
  $Result = [pscustomobject]@{Code=$Process.ExitCode;Text=($OutputTask.Result + $ErrorTask.Result)}
  $Process.Dispose()
  return $Result
}

try {
  $Guarded = Join-Path $Base 'missing-component-entry'
  New-Item -ItemType Directory -Path (Join-Path $Guarded 'lib') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $Repo 'scripts\launch-tui.ps1') -Destination $Guarded
  Set-Content -LiteralPath (Join-Path $Guarded '.home-edge-launcher-owned') -Value 'home-edge-bootstrap/registered-launcher/v1' -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $Guarded 'target.txt') -Value 'fixture-original-target' -Encoding ASCII
  foreach ($Missing in @('project-location.ps1', 'ui-language.ps1', 'host-launcher.ps1')) {
    foreach ($Component in @('project-location.ps1', 'ui-language.ps1', 'host-launcher.ps1')) {
      Copy-Item -LiteralPath (Join-Path $Repo ('scripts\lib\' + $Component)) -Destination (Join-Path $Guarded 'lib') -Force
    }
    Remove-Item -LiteralPath (Join-Path $Guarded ('lib\' + $Missing))
    $BeforeSnapshot = @(Get-ChildItem -LiteralPath $Guarded -Recurse -Force | Sort-Object FullName | ForEach-Object {
      $_.FullName + '|' + $(if ($_.PSIsContainer) { 'directory' } else { (Get-FileHash -LiteralPath $_.FullName).Hash })
    }) -join "`n"
    $MissingStartup = Invoke-Entry (Join-Path $Guarded 'launch-tui.ps1') '-Version'
    if ($MissingStartup.Code -ne 2 -or $MissingStartup.Text -notmatch 'startup_state=failed' -or
        -not $MissingStartup.Text.Contains('missing_component=lib/' + $Missing) -or
        $MissingStartup.Text -notmatch '请恢复完整项目' -or $MissingStartup.Text -notmatch 'Restore the complete project' -or
        $MissingStartup.Text -match 'project_location_state=') { throw ('Missing component did not reject with recovery guidance: ' + $MissingStartup.Text) }
    $AfterSnapshot = @(Get-ChildItem -LiteralPath $Guarded -Recurse -Force | Sort-Object FullName | ForEach-Object {
      $_.FullName + '|' + $(if ($_.PSIsContainer) { 'directory' } else { (Get-FileHash -LiteralPath $_.FullName).Hash })
    }) -join "`n"
    if ($BeforeSnapshot -cne $AfterSnapshot) { throw 'Damaged registration wrote files' }
  }
  Write-Host 'launcher_missing_component_fixtures=ready'
  if ($MissingComponentsOnly) { exit 0 }
  $Copy = Join-Path $Base ("portable copy & " + [char]0x4e2d + [char]0x6587)
  $Scripts = Join-Path $Copy "scripts"
  New-Item -ItemType Directory -Path $Scripts | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $Scripts "lib") | Out-Null
  Copy-Item -LiteralPath (Join-Path $Repo "PROJECT") -Destination $Copy
  Set-Content -LiteralPath (Join-Path $Copy "README.md") -Value "fixture" -Encoding ASCII
  Copy-Item -LiteralPath (Join-Path $Repo "scripts\launch-tui.ps1") -Destination $Scripts
  Copy-Item -LiteralPath (Join-Path $Repo "scripts\lib\project-location.ps1") -Destination (Join-Path $Scripts "lib")
  Copy-Item -LiteralPath (Join-Path $Repo "scripts\lib\host-launcher.ps1") -Destination (Join-Path $Scripts "lib")
  Copy-Item -LiteralPath (Join-Path $Repo "scripts\lib\ui-language.ps1") -Destination (Join-Path $Scripts "lib")
  Copy-Item -LiteralPath (Join-Path $Repo "start.cmd") -Destination $Copy
  Copy-Item -LiteralPath (Join-Path $Repo "scripts\tui.ps1") -Destination $Scripts
  Copy-Item -LiteralPath (Join-Path $Repo "scripts\create-desktop-shortcut.ps1") -Destination $Scripts
  Set-Content -LiteralPath (Join-Path $Copy "VERSION") -Value "vfixture" -Encoding ASCII
  foreach ($Name in @("doctor.ps1","run-bootstrap.ps1","check-no-wall-readiness.ps1","export-support-bundle.ps1","decommission-merlin.ps1")) {
    Set-Content -LiteralPath (Join-Path $Scripts $Name) -Value 'throw "Startup must not dispatch an operation"' -Encoding ASCII
  }
  Set-Content -LiteralPath (Join-Path $Scripts "doctor.ps1") -Value 'param([switch]$Json,[string]$Router); Write-Host ("fixture_target=" + $Router)' -Encoding ASCII
  $Start = Join-Path $Copy "start.cmd"
  $HelpResult = Invoke-Entry $Start "-Help"
  if ($HelpResult.Code -ne 0 -or $HelpResult.Text -notmatch "usage:") { throw "Launcher failed from unrelated cwd or Unicode/space/ampersand path" }
  $VersionResult = Invoke-Entry $Start "-Version"
  if ($VersionResult.Code -ne 0 -or $VersionResult.Text -notmatch "home-edge-bootstrap vfixture") { throw "Launcher did not resolve its own package" }
  $MenuResult = Invoke-Entry $Start "-Language en -NoColor -Router user@router.lan" "0`n"
  if ($MenuResult.Code -ne 0 -or $MenuResult.Text -notmatch "Home Edge Guide" -or $MenuResult.Text -match "fixture_target=") { throw "Opening the guide should show the menu without dispatching actions" }
  $Forwarded = Invoke-Entry $Start "-Language en -NoColor -Router user@router.lan" "2`n0`n"
  if ($Forwarded.Code -ne 0 -or $Forwarded.Text -notmatch "fixture_target=user@router.lan") { throw "Launcher did not forward the router argument to the selected action" }
  $InvalidResult = Invoke-Entry $Start "-Language invalid"
  if ($InvalidResult.Code -ne 2) { throw "Launcher lost the guide failure exit code" }
  $ExplicitEnglish = Invoke-Entry $Start '-Language en -Help -Router forbidden' '' 'zh-CN'
  if ($ExplicitEnglish.Code -ne 0 -or $ExplicitEnglish.Text -notmatch 'Language priority:') { throw 'Explicit English did not override language environment' }
  $ExplicitChinese = Invoke-Entry $Start '-Language zh-CN -Help' '' 'en'
  if ($ExplicitChinese.Code -ne 0 -or $ExplicitChinese.Text -notmatch '语言顺序：') { throw 'Explicit Chinese did not override language environment' }
  $ChineseSelection = Invoke-Entry (Join-Path $Scripts 'launch-tui.ps1') ('-Repo "' + (Join-Path $Base 'absent') + '" -Version') '' 'zh-CN'
  if ($ChineseSelection.Code -ne 2 -or $ChineseSelection.Text -notmatch '启动已取消' -or $ChineseSelection.Text -match 'home-edge-bootstrap vfixture') { throw 'Chinese selection EOF did not cancel with localized guidance' }
  . (Join-Path $Scripts 'lib\ui-language.ps1')
  $SavedLanguageEnvironment = $env:HOME_EDGE_LANGUAGE
  try {
    $env:HOME_EDGE_LANGUAGE = 'en'
    if ((Resolve-HomeEdgeUiLanguage -ExplicitLanguage 'zh-CN' -HostLocale 'en-US') -cne 'zh-CN' -or
        (Resolve-HomeEdgeUiLanguage -HostLocale 'zh-TW') -cne 'en') { throw 'Language priority is incorrect' }
    $env:HOME_EDGE_LANGUAGE = 'invalid'
    if ((Resolve-HomeEdgeUiLanguage -HostLocale 'zh-TW') -cne 'zh-CN' -or
        (Resolve-HomeEdgeUiLanguage -HostLocale 'fr-FR') -cne 'en' -or
        (Resolve-HomeEdgeUiLanguage -HostLocale '') -cne 'zh-CN') { throw 'Host culture language selection is incorrect' }
  } finally { $env:HOME_EDGE_LANGUAGE = $SavedLanguageEnvironment }
  $Incomplete = Join-Path $Base "incomplete"
  New-Item -ItemType Directory -Path $Incomplete | Out-Null
  Copy-Item -LiteralPath $Start -Destination $Incomplete
  $MissingResult = Invoke-Entry (Join-Path $Incomplete "start.cmd")
  if ($MissingResult.Code -ne 2 -or $MissingResult.Text -notmatch "Extract the WHOLE ZIP") { throw "Incomplete extraction did not give actionable guidance" }
  $Desktop = Join-Path $Base "fixture desktop"
  New-Item -ItemType Directory -Path $Desktop | Out-Null
  $Helper = Join-Path $Scripts "create-desktop-shortcut.ps1"
  $Installed = Join-Path $Base "registered entry"
  $InstallArguments = '-DestinationDirectory "' + $Desktop + '" -LauncherDirectory "' + $Installed + '"'
  $ShortcutResult = Invoke-Entry $Helper $InstallArguments
  if ($ShortcutResult.Code -ne 0) { throw ("Shortcut creation failed: " + $ShortcutResult.Text) }
  $InstalledLanguageHelper = Join-Path $Installed 'lib\ui-language.ps1'
  if (-not (Test-Path -LiteralPath $InstalledLanguageHelper -PathType Leaf)) { throw 'Registered launcher omitted the language helper' }
  $Shell = New-Object -ComObject WScript.Shell
  $LinkPath = Join-Path $Desktop "Home Edge Bootstrap.lnk"
  $Link = $Shell.CreateShortcut($LinkPath)
  if ($Link.TargetPath -ne (Join-Path $Installed "home-edge.cmd") -or $Link.WorkingDirectory -ne $Installed) { throw "Shortcut does not point to the independent registered launcher" }
  $ViaLink = Invoke-Entry $Link.TargetPath "-Version"
  if ($ViaLink.Code -ne 0 -or $ViaLink.Text -notmatch "home-edge-bootstrap vfixture") { throw "Registered entry cannot validate and launch its project" }
  $Again = Invoke-Entry $Helper $InstallArguments
  if ($Again.Code -ne 0 -or $Again.Text -notmatch "shortcut_state=reused") { throw "Same target should reuse its registration" }
  Remove-Item -LiteralPath $InstalledLanguageHelper
  $CancelledUpgrade = Invoke-Entry $Helper $InstallArguments
  if ($CancelledUpgrade.Code -ne 0 -or $CancelledUpgrade.Text -notmatch 'shortcut_state=cancelled' -or
      (Test-Path -LiteralPath $InstalledLanguageHelper)) { throw 'Missing helper refresh wrote without explicit confirmation' }
  $Upgraded = Invoke-Entry $Helper $InstallArguments "REPLACE`nAPPLY`n"
  if ($Upgraded.Code -ne 0 -or -not (Test-Path -LiteralPath $InstalledLanguageHelper) -or
      (Get-FileHash -LiteralPath $InstalledLanguageHelper).Hash -cne (Get-FileHash -LiteralPath (Join-Path $Scripts 'lib\ui-language.ps1')).Hash) { throw 'Old registration did not recover a missing language helper' }
  $SavedTarget = [IO.File]::ReadAllText((Join-Path $Installed "target.txt"))
  $SecondCopy = Join-Path $Base "another project copy"
  Copy-Item -LiteralPath $Copy -Destination $SecondCopy -Recurse
  $SecondHelper = Join-Path $SecondCopy "scripts\create-desktop-shortcut.ps1"
  foreach ($InputText in @("", "REPLACE`n", "REPLACE`napply`n")) {
    $Rejected = Invoke-Entry $SecondHelper $InstallArguments $InputText
    if ($Rejected.Code -ne 0 -or $Rejected.Text -notmatch "shortcut_state=cancelled" -or
        [IO.File]::ReadAllText((Join-Path $Installed "target.txt")) -cne $SavedTarget) { throw "Retarget cancellation changed registration" }
  }
  $Retargeted = Invoke-Entry $SecondHelper $InstallArguments "REPLACE`nAPPLY`n"
  if ($Retargeted.Code -ne 0 -or [IO.File]::ReadAllLines((Join-Path $Installed "target.txt"))[1] -ne $SecondCopy) { throw "Explicit two-token retarget did not use selected copy" }
  $RestoredTarget = Invoke-Entry $Helper $InstallArguments "REPLACE`nAPPLY`n"
  if ($RestoredTarget.Code -ne 0 -or [IO.File]::ReadAllLines((Join-Path $Installed "target.txt"))[1] -ne $Copy) { throw "Explicit restore did not rebind original copy" }
  $Moved = Join-Path $Base "moved project copy"
  Move-Item -LiteralPath $Copy -Destination $Moved
  $Stale = Invoke-Entry $Link.TargetPath "-Version"
  if ($Stale.Code -ne 2 -or $Stale.Text -notmatch "needs_selection") { throw "Moved project was not detected" }
  Copy-Item -LiteralPath $Moved -Destination $Copy -Recurse
  $Replaced = Invoke-Entry $Link.TargetPath "-Version"
  if ($Replaced.Code -ne 2 -or $Replaced.Text -notmatch "different directory instance" -or $Replaced.Text -match "home-edge-bootstrap vfixture") { throw "Another copy at the old location was silently executed" }
  $Recovered = Invoke-Entry $Link.TargetPath "-Version" ($Base + "`n" + $Moved + "`n")
  if ($Recovered.Code -ne 0 -or $Recovered.Text -notmatch "home-edge-bootstrap vfixture") { throw "Registered launcher did not recover from an invalid selection and relocation" }
  $TargetLines = [IO.File]::ReadAllLines((Join-Path $Installed "target.txt"))
  if ($TargetLines[1] -ne $Moved) { throw "Relocated project registration was not persisted" }
  $Helper = Join-Path $Moved "scripts\create-desktop-shortcut.ps1"
  $Identity = Join-Path $Moved "PROJECT"
  Set-Content -LiteralPath $Identity -Value "unrelated-project" -Encoding ASCII
  $WrongProject = Invoke-Entry $Link.TargetPath "-Version"
  if ($WrongProject.Code -ne 2 -or $WrongProject.Text -match "home-edge-bootstrap vfixture") { throw "Invalid project identity was executed" }
  Copy-Item -LiteralPath (Join-Path $Repo "PROJECT") -Destination $Identity -Force
  $QuotedCopy = $Moved + "'"
  Copy-Item -LiteralPath $Moved -Destination $QuotedCopy -Recurse
  . (Join-Path $Repo "scripts\lib\project-location.ps1")
  if ((Resolve-HomeEdgeProject $QuotedCopy) -ne $QuotedCopy) { throw "Literal apostrophe in an existing directory changed the selected copy" }
  $TargetRecord = Join-Path $Installed "target.txt"
  Remove-Item -LiteralPath $TargetRecord
  New-Item -ItemType Directory -Path $TargetRecord | Out-Null
  $WrongType = Invoke-Entry $Helper $InstallArguments
  if ($WrongType.Code -ne 1) { throw "Unexpected registration leaf type was overwritten" }
  Remove-Item -LiteralPath $TargetRecord
  $Restored = Invoke-Entry $Helper $InstallArguments
  if ($Restored.Code -ne 0) { throw "Valid registration cannot recover after removing an invalid leaf" }
  $ForeignLibrary = Join-Path $Base "foreign library"
  New-Item -ItemType Directory -Path $ForeignLibrary | Out-Null
  Set-Content -LiteralPath (Join-Path $ForeignLibrary "user-file") -Value "untouched" -Encoding ASCII
  $Library = Join-Path $Installed "lib"
  Move-Item -LiteralPath $Library -Destination ($Library + ".saved")
  New-Item -ItemType Junction -Path $Library -Target $ForeignLibrary | Out-Null
  $JunctionResult = Invoke-Entry $Helper $InstallArguments
  if ($JunctionResult.Code -ne 1 -or (Get-Content -Raw -LiteralPath (Join-Path $ForeignLibrary "user-file")).Trim() -ne "untouched") { throw "Registration wrote through a library junction" }
  [IO.Directory]::Delete($Library)
  Move-Item -LiteralPath ($Library + ".saved") -Destination $Library
  $InterruptedDirectory = Join-Path $Base "interrupted empty setup"
  New-Item -ItemType Directory -Path (Join-Path $InterruptedDirectory "lib") -Force | Out-Null
  $EmptyRetry = Invoke-Entry $Helper ('-DestinationDirectory "' + $Desktop + '" -LauncherDirectory "' + $InterruptedDirectory + '"')
  if ($EmptyRetry.Code -ne 0) { throw "Interrupted empty setup cannot be retried" }
  $Link.TargetPath = Join-Path $env:SystemRoot "notepad.exe"
  $Link.Description = "User shortcut"
  $Link.Save()
  $Before = (Get-FileHash -LiteralPath $LinkPath -Algorithm SHA256).Hash
  $Collision = Invoke-Entry $Helper $InstallArguments
  if ($Collision.Code -ne 1 -or (Get-FileHash -LiteralPath $LinkPath -Algorithm SHA256).Hash -ne $Before) { throw "Unrelated shortcut was overwritten" }
  Write-Host "launcher_fixture_tests=ready"
} finally {
  if ((Resolve-Path -LiteralPath $Base).Path -ne [IO.Path]::GetFullPath($Base)) { throw "Unexpected fixture cleanup path" }
  Remove-Item -LiteralPath $Base -Recurse -Force
}
