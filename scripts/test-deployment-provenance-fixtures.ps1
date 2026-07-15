param([string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path)
$ErrorActionPreference = "Stop"
$Base = Join-Path ([IO.Path]::GetTempPath()) ("home-edge-provenance-test-ps-" + $PID)
$Source = Join-Path $Base "source"
$Stage = Join-Path $Base "stage"
try {
  New-Item -ItemType Directory -Force $Source, (Join-Path $Stage "scripts"), (Join-Path $Stage "config") | Out-Null
  Set-Content -LiteralPath (Join-Path $Stage "scripts\self-heal.sh") -Value "managed" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $Stage "config\policy.env") -Value "HEAL_DRY_RUN=1" -Encoding ASCII
  & git -C $Source init -q
  & git -C $Source config user.email fixture@example.invalid
  & git -C $Source config user.name fixture
  & git -C $Source config core.autocrlf false
  Set-Content -LiteralPath (Join-Path $Source "source.txt") -Value "source" -Encoding ASCII
  & git -C $Source add source.txt
  & git -C $Source commit -qm baseline
  $Commit = (& git -C $Source rev-parse HEAD).Trim()
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\new-deployment-provenance.ps1") -StageRoot $Stage -SourceRoot $Source
  if ($LASTEXITCODE -ne 0) { throw "PowerShell provenance generator failed" }
  $Metadata = Get-Content -LiteralPath (Join-Path $Stage "DEPLOYMENT-PROVENANCE.env")
  if ($Metadata -notcontains "source_kind=git" -or $Metadata -notcontains "source_commit=$Commit") { throw "PowerShell source identity mismatch" }
  $ContentId = ($Metadata | Where-Object { $_ -like "content_id=*" }).Substring(11)
  $ActualId = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Stage "DEPLOYMENT-CONTENT-SHA256SUMS")).Hash.ToLowerInvariant()
  if ($ContentId -ne $ActualId) { throw "PowerShell content id does not hash actual checksum bytes" }
  foreach ($Line in Get-Content -LiteralPath (Join-Path $Stage "DEPLOYMENT-CONTENT-SHA256SUMS")) {
    if ($Line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "malformed checksum line" }
    $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Stage $Matches[2])).Hash.ToLowerInvariant()
    if ($Actual -ne $Matches[1]) { throw "PowerShell staged byte mismatch" }
  }
}
finally { Remove-Item -LiteralPath $Base -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "deployment_provenance_fixture_tests=ok"
