param(
  [Parameter(Mandatory = $true)][string]$Repo,
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$PreparedDir,
  [Parameter(Mandatory = $true)][string]$Output,
  [string]$Commit = "HEAD",
  [switch]$FixtureMode
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
$Arguments = @((Join-Path $PSScriptRoot "public-release.py"), "build", "--repo", $Repo, "--version", $Version, "--prepared-dir", $PreparedDir, "--output", $Output, "--commit", $Commit)
if ($FixtureMode) { $Arguments += "--fixture-mode" }
& $Python @Arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
