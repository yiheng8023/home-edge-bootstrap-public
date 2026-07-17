param([string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path)
$ErrorActionPreference = "Stop"
$Base = Join-Path ([IO.Path]::GetTempPath()) ("home-edge-decommission-host-test-ps-" + $PID)
$FakeBin = Join-Path $Base "bin"
$SshLog = Join-Path $Base "ssh.log"
$Payload = Join-Path $Base "payload.b64"
$OldPath = $env:PATH

try {
  New-Item -ItemType Directory -Force $FakeBin | Out-Null
  Set-Content -LiteralPath $SshLog -Value "" -NoNewline
  $FakeSsh = Join-Path $FakeBin "ssh.cmd"
  Set-Content -LiteralPath $FakeSsh -Encoding ASCII -Value @(
    "@echo off",
    'echo %*>>"%DECOMMISSION_SSH_LOG%"',
    '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "[IO.File]::WriteAllText($env:DECOMMISSION_SSH_PAYLOAD,[Console]::In.ReadToEnd(),(New-Object Text.UTF8Encoding($false)))"',
    "echo decommission_state=plan_ready",
    "exit /b 0"
  )
  $env:PATH = "$FakeBin;$OldPath"
  $env:DECOMMISSION_SSH_LOG = $SshLog
  $env:DECOMMISSION_SSH_PAYLOAD = $Payload
  $Wrapper = Join-Path $Repo "scripts\decommission-merlin.ps1"
  if (-not (Test-Path -LiteralPath $Wrapper -PathType Leaf)) { throw "missing PowerShell decommission wrapper" }

  & $Wrapper -Router 'user@192.168.50.1' -KnownHostsFile (Join-Path $Base "known_hosts") -NoPause
  if ($LASTEXITCODE -ne 0) { throw "PowerShell plan wrapper failed" }
  $PlanLog = Get-Content -LiteralPath $SshLog -Raw
  if ($PlanLog -notmatch 'DECOMMISSION_APPLY=0') { throw "PowerShell plan did not stream apply=0" }
  if ($PlanLog -notmatch 'user@192\.168\.50\.1') { throw "PowerShell plan omitted router target" }
  $Archive = Join-Path $Base "payload.tgz"
  [IO.File]::WriteAllBytes($Archive, [Convert]::FromBase64String((Get-Content -LiteralPath $Payload -Raw).Trim()))
  $ArchiveList = @(& tar.exe -tzf $Archive | ForEach-Object { $_.TrimStart('.','/').Trim() } | Where-Object { $_ })
  if ($LASTEXITCODE -ne 0) { throw "PowerShell payload was not a valid tar archive" }
  $Expected = @("decommission-router-state.sh", "migrate-router-state.sh")
  if ((Compare-Object $Expected $ArchiveList).Count -ne 0) { throw "PowerShell payload contained files outside the two-script allowlist: $($ArchiveList -join ',')" }

  Set-Content -LiteralPath $SshLog -Value "" -NoNewline
  & $Wrapper -Router 'user@192.168.50.1' -Apply -Confirmation 'WRONG' -NoPause 2>$null
  if ($LASTEXITCODE -ne 2) { throw "PowerShell wrong confirmation did not exit 2" }
  if ((Get-Content -LiteralPath $SshLog -Raw).Length -ne 0) { throw "PowerShell wrong confirmation contacted SSH" }

  & $Wrapper -Router 'user@192.168.50.1' -Apply -Confirmation 'DECOMMISSION' -KnownHostsFile (Join-Path $Base "known_hosts") -NoPause
  if ($LASTEXITCODE -ne 0) { throw "PowerShell apply wrapper failed" }
  $ApplyLog = Get-Content -LiteralPath $SshLog -Raw
  if ($ApplyLog -notmatch 'DECOMMISSION_APPLY=1' -or $ApplyLog -notmatch 'DECOMMISSION_CONFIRMATION=DECOMMISSION') { throw "PowerShell apply omitted exact gated environment" }

  Set-Content -LiteralPath $SshLog -Value "" -NoNewline
  & $Wrapper -Router 'user@router;unsafe' -NoPause 2>$null
  if ($LASTEXITCODE -ne 2) { throw "PowerShell invalid router did not exit 2" }
  if ((Get-Content -LiteralPath $SshLog -Raw).Length -ne 0) { throw "PowerShell invalid router contacted SSH" }
}
finally {
  $env:PATH = $OldPath
  Remove-Item Env:\DECOMMISSION_SSH_LOG -ErrorAction SilentlyContinue
  Remove-Item Env:\DECOMMISSION_SSH_PAYLOAD -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Base -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "decommission_host_fixture_tests=ok"
