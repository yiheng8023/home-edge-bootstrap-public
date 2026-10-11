function Resolve-HomeEdgeProject([string]$Candidate) {
  if (-not $Candidate) { throw "Choose the complete cloned or extracted project folder." }
  if (-not (Test-Path -LiteralPath $Candidate)) {
    $Wrapped = $Candidate.Trim()
    if ($Wrapped.Length -ge 2 -and (($Wrapped[0] -eq '"' -and $Wrapped[$Wrapped.Length - 1] -eq '"') -or
        ($Wrapped[0] -eq "'" -and $Wrapped[$Wrapped.Length - 1] -eq "'"))) {
      $Candidate = $Wrapped.Substring(1, $Wrapped.Length - 2)
    }
  }
  if ($Candidate -match "[\r\n]") { throw "The project path cannot contain a line break." }
  $Item = Get-Item -LiteralPath $Candidate -ErrorAction Stop
  if (-not $Item.PSIsContainer) { throw "Choose a folder, not a ZIP file or an individual script." }
  $Root = $Item.FullName
  $Identity = Join-Path $Root "PROJECT"
  if (-not (Test-Path -LiteralPath $Identity -PathType Leaf) -or
      [IO.File]::ReadAllText($Identity).Trim() -cne "home-edge-bootstrap/project/v1") {
    throw "This is not a Home Edge Bootstrap project folder (PROJECT identity is missing or invalid)."
  }
  foreach ($Required in @("README.md", "scripts/tui.ps1", "scripts/launch-tui.ps1", "scripts/lib/project-location.ps1")) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Required) -PathType Leaf)) {
      throw "The project folder is incomplete: missing $Required. Extract the whole package or update the complete clone."
    }
  }
  return $Root
}
