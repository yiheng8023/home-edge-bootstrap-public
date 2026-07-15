param(
  [Parameter(Mandatory = $true)][string]$Repo,
  [Parameter(Mandatory = $true)][string]$Dist,
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$Commit = "HEAD"
)
$ErrorActionPreference = "Stop"
$Python = $null
foreach ($Candidate in @("python", "python3")) {
  $Command = Get-Command $Candidate -ErrorAction SilentlyContinue
  if ($Command) {
    & $Command.Source -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)'
    if ($LASTEXITCODE -eq 0) { $Python = $Command.Source; break }
  }
}
if (-not $Python) { throw "Python 3 is required" }
& $Python (Join-Path $PSScriptRoot "public-release.py") verify --repo $Repo --dist $Dist --version $Version --commit $Commit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
