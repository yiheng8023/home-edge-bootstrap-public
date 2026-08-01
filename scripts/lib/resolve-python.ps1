function Resolve-Python3 {
  param([string]$FailureMessage = "Python 3 is required")

  foreach ($Name in @("python3", "python")) {
    foreach ($Command in @(Get-Command $Name -All -CommandType Application -ErrorAction SilentlyContinue)) {
      try {
        & $Command.Source -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)' *> $null
        if ($LASTEXITCODE -eq 0) { return [string]$Command.Source }
      }
      catch {
        continue
      }
    }
  }
  throw $FailureMessage
}
