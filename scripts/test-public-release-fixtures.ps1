$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Python = $null
foreach ($Candidate in @("python", "python3")) {
  $Command = Get-Command $Candidate -ErrorAction SilentlyContinue
  if ($Command) {
    & $Command.Source -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)'
    if ($LASTEXITCODE -eq 0) { $Python = $Command.Source; break }
  }
}
if (-not $Python) { throw "Python 3 is required" }
& $Python (Join-Path $PSScriptRoot "test-public-release-fixtures.py") --mode powershell --source $Repo
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
