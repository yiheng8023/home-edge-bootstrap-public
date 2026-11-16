param([string]$Repo=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$Entry=Join-Path $Repo 'scripts/enable-service-health.ps1'
$Errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($Entry,[ref]$null,[ref]$Errors)
if ($Errors.Count) {throw ($Errors.Message -join '; ')}
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('home-edge-enable-fixture.'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($Temp)
$global:ServiceHealthFixturePayload='';$global:ServiceHealthFixtureTransfers=0
function ssh {
  $Command=$args[-1];$global:LASTEXITCODE=0
  if ($Command -like '*uname -m*') {'aarch64'}
  elseif ($Command -like 'tr -d*') {$global:ServiceHealthFixturePayload=(@($input)-join "`n").Replace("`r",'');'service_health_enable=fixture'}
}
function scp {$global:ServiceHealthFixtureTransfers++;$global:LASTEXITCODE=0}
try {
  $Binary=Join-Path $Temp 'binary';[IO.File]::WriteAllText($Binary,'fixture binary')
  $Digest=(Get-FileHash -LiteralPath $Binary -Algorithm SHA256).Hash
  & $Entry -Router 'user@router' -PrebuiltBinary $Binary -ExpectedSha256 $Digest
  if ($global:ServiceHealthFixtureTransfers -ne 2 -or $global:ServiceHealthFixturePayload -notmatch "(?m)^apply='0'$" -or $global:ServiceHealthFixturePayload -notmatch 'SERVICE_HEALTH_PROFILES=gemini') {throw 'PLAN transport/boundary mismatch'}
  & $Entry -Router 'user@router' -Apply -PrebuiltBinary $Binary -ExpectedSha256 $Digest
  if ($global:ServiceHealthFixturePayload -notmatch "(?m)^apply='1'$") {throw 'Apply was not explicit'}
  & $Entry -Router 'user@router' -Apply -ToolsOnly -PrebuiltBinary $Binary -ExpectedSha256 $Digest
  if ($global:ServiceHealthFixturePayload -notmatch "(?m)^tools_only='1'$") {throw 'Tools-only boundary missing'}
  $Rejected=$false;try {& $Entry -Router 'user@router' -PrebuiltBinary $Binary -ExpectedSha256 ('0'*64)} catch {$Rejected=$true}
  if (-not $Rejected) {throw 'Wrong digest accepted'}
  $Rejected=$false;try {& $Entry -Router 'user@router;bad' -PrebuiltBinary $Binary -ExpectedSha256 $Digest} catch {$Rejected=$true}
  if (-not $Rejected) {throw 'Unsafe destination accepted'}
  'service_health_enable_powershell_fixture_tests=passed'
} finally {
  Remove-Item -LiteralPath (Join-Path $Temp 'binary') -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Temp -ErrorAction SilentlyContinue
}
