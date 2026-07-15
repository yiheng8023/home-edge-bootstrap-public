param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$BundleDir = Join-Path $Repo "bundle"
$RequiredTools = @("ssh", "tar")
$MissingTools = @()

Write-Host "# No-Wall Readiness"
Write-Host ""
Write-Host "## Local Tools"
foreach ($Tool in $RequiredTools) {
  if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
    $MissingTools += $Tool
  }
}
if ($MissingTools.Count) {
  Write-Host "status=missing_tools"
  Write-Host "missing_tools=$($MissingTools -join ' ')"
}
else {
  Write-Host "status=tools_ready"
}

Write-Host ""
Write-Host "## Offline Bundle"
$RequiredFiles = @("mihomo-linux-arm64", "ShellCrash.tar.gz", "SHA256SUMS", "MANIFEST.json")
$BundleReady = $true
foreach ($File in $RequiredFiles) {
  $Path = Join-Path $BundleDir $File
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $Item = Get-Item -LiteralPath $Path
    if ($Item.Length -gt 0) {
      Write-Host "bundle/$File=present"
      continue
    }
  }
  Write-Host "bundle/$File=missing"
  $BundleReady = $false
}

if ($BundleReady) {
  $SumsPath = Join-Path $BundleDir "SHA256SUMS"
  $Failures = @()
  foreach ($Line in Get-Content -LiteralPath $SumsPath) {
    if (-not $Line.Trim()) { continue }
    $Parts = $Line -split "\s+", 2
    if ($Parts.Count -lt 2) { continue }
    $Expected = $Parts[0].ToLowerInvariant()
    $Name = $Parts[1].Trim()
    $Path = Join-Path $BundleDir $Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
      $Failures += "$Name missing"
      continue
    }
    $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($Actual -ne $Expected) {
      $Failures += "$Name sha256 mismatch"
    }
  }
  if ($Failures.Count) {
    Write-Host "bundle_state=invalid"
    $Failures | ForEach-Object { Write-Host $_ }
    exit 1
  }
  Write-Host "bundle_state=verified"
}
else {
  Write-Host "bundle_state=missing"
}

Write-Host ""
Write-Host "## Interpretation"
if ($MissingTools.Count) {
  Write-Host "Install or repair missing local tools before operating without proxy."
  exit 1
}
elseif ($BundleReady) {
  Write-Host "This checkout can perform a no-wall runtime restore when the target router is supported."
}
else {
  Write-Host "This checkout can configure an existing ShellCrash/Mihomo runtime, but cannot perform a fresh no-wall runtime install until the bundle is supplied from a trusted reachable source."
}
