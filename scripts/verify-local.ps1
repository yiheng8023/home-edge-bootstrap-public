param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$SbomPath = "",
  [switch]$SbomOnly
)

$ErrorActionPreference = "Stop"

function Run-RequiredPowerShellFixture([string]$Name) {
  $Path = Join-Path $Repo "scripts\$Name"
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing required PowerShell fixture: $Name" }
  & $Path -Repo $Repo
}

function Run-RequiredShellFixture([string]$Name) {
  $Path = Join-Path $Repo "scripts\$Name"
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing required POSIX fixture: $Name" }
  & sh $Path
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Get-Python3Command {
  foreach ($Name in @("python3", "python")) {
    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $Command) { continue }
    & $Command.Source -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)'
    if ($LASTEXITCODE -eq 0) { return [string]$Command.Source }
  }
  throw "Python 3 is required for POSIX local verification; Python 2 is unsupported"
}

function Assert-PublicSbom([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "SBOM path does not exist: $Path" }
  $Sbom = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  if ($Sbom.spdxVersion -cne "SPDX-2.3" -or $Sbom.dataLicense -cne "CC0-1.0" -or $Sbom.SPDXID -cne "SPDXRef-DOCUMENT") { throw "invalid SPDX document identity" }
  if (@($Sbom.packages).Count -ne 3) { throw "invalid SPDX package structure" }
  $ActualRelationships = @($Sbom.relationships | ForEach-Object { "$($_.spdxElementId)|$($_.relationshipType)|$($_.relatedSpdxElement)" })
  [System.Array]::Sort($ActualRelationships, [System.StringComparer]::Ordinal)
  $ExpectedRelationships = @(
    "SPDXRef-DOCUMENT|DESCRIBES|SPDXRef-Package-Source",
    "SPDXRef-Package-Mihomo|OPTIONAL_COMPONENT_OF|SPDXRef-Package-Source",
    "SPDXRef-Package-ShellCrash|OPTIONAL_COMPONENT_OF|SPDXRef-Package-Source"
  )
  [System.Array]::Sort($ExpectedRelationships, [System.StringComparer]::Ordinal)
  if (($ActualRelationships -join "`n") -cne ($ExpectedRelationships -join "`n")) { throw "invalid SPDX relationship triples" }
}

if (-not $SbomPath) { $SbomPath = Join-Path $Repo "config\sbom.json" }
if ($SbomOnly) {
  Assert-PublicSbom $SbomPath
  Write-Host "sbom_structure_state=ready"
  return
}

Write-Host "# Public Local Verification"
Write-Host "verification_network_boundary=local_only"

Get-ChildItem -LiteralPath (Join-Path $Repo "scripts") -Filter "*.ps1" | ForEach-Object {
  $Tokens = $null
  $Errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$Tokens, [ref]$Errors) | Out-Null
  if ($Errors.Count) { throw "PowerShell parse failed: $($_.Name): $($Errors[0].Message)" }
}
Write-Host "ps1_parse=ok"

$HasSh = $null -ne (Get-Command sh -ErrorAction SilentlyContinue)
if ($HasSh) {
  Get-ChildItem -LiteralPath (Join-Path $Repo "scripts") -Filter "*.sh" | ForEach-Object {
    & sh -n $_.FullName
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }
  & sh -n (Join-Path $Repo "bootstrap.sh")
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  Write-Host "sh_syntax=ok"
}
else { Write-Host "sh_syntax=skipped_no_sh" }

$RequiredPowerShellFixtures = @(
  "test-host-ssh-fixtures.ps1",
  "test-client-topology-fixtures.ps1",
  "test-installation-closeout-client-fixtures.ps1",
  "test-edge-health-fixtures.ps1",
  "test-doctor-fixtures.ps1",
  "test-router-status-fixtures.ps1",
  "test-run-bootstrap-fixtures.ps1",
  "test-tui-fixtures.ps1",
  "test-guide-router-fixtures.ps1",
  "test-deployment-provenance-fixtures.ps1",
  "test-deploy-fixtures.ps1",
  "test-support-bundle-fixtures.ps1",
  "test-third-party-compliance-fixtures.ps1",
  "test-public-release-fixtures.ps1"
)
foreach ($Fixture in $RequiredPowerShellFixtures) { Run-RequiredPowerShellFixture $Fixture }

if ($HasSh) {
  $Python3Command = Get-Python3Command
  Write-Host "python3_runtime_state=ready"
  $RequiredShellFixtures = @(
    "test-host-ssh-fixtures.sh",
    "test-self-heal-fixtures.sh",
    "test-enable-live-self-heal-fixtures.sh",
    "test-merlin-adapter-fixtures.sh",
    "test-bundle-fixtures.sh",
    "test-rollback-fixtures.sh",
    "test-subscription-fixtures.sh",
    "test-client-topology-fixtures.sh",
    "test-installation-closeout-client-fixtures.sh",
    "test-edge-health-fixtures.sh",
    "test-doctor-fixtures.sh",
    "test-router-status-fixtures.sh",
    "test-run-bootstrap-fixtures.sh",
    "test-tui-fixtures.sh",
    "test-guide-router-fixtures.sh",
    "test-deployment-provenance-fixtures.sh",
    "test-deploy-fixtures.sh",
    "test-secret-scan-fixtures.sh",
    "test-support-bundle-fixtures.sh",
    "test-third-party-compliance-fixtures.sh",
    "test-public-release-fixtures.sh"
  )
  foreach ($Fixture in $RequiredShellFixtures) { Run-RequiredShellFixture $Fixture }
}

& (Join-Path $Repo "scripts\verify-compatibility-matrix.ps1") -Repo $Repo
& (Join-Path $Repo "scripts\scan-secrets.ps1") -Repo $Repo -ScanPath $Repo
& (Join-Path $Repo "scripts\verify-media-kit.ps1") -Root $Repo

foreach ($Required in @("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md")) {
  if (-not (Test-Path -LiteralPath (Join-Path $Repo $Required) -PathType Leaf)) { throw "missing license material: $Required" }
}
$License = [System.IO.File]::ReadAllText((Join-Path $Repo "LICENSE"))
if ($License -notmatch "Apache License" -or $License -notmatch "Version 2\.0") { throw "Apache-2.0 license text missing" }
$ThirdParty = [System.IO.File]::ReadAllText((Join-Path $Repo "THIRD_PARTY_NOTICES.md"))
foreach ($Fact in @("Mihomo", "ShellCrash", "GPL-3.0-only")) {
  if ($ThirdParty.IndexOf($Fact, [System.StringComparison]::Ordinal) -lt 0) { throw "third-party license fact missing: $Fact" }
}
Write-Host "license_material_state=ready"

Assert-PublicSbom $SbomPath
Write-Host "sbom_structure_state=ready"

Write-Host "release_fixture_state=ready"
Write-Host "public_media_kit_state=ready"

$RequiredPaths = @(
  ".github/workflows/verify.yml", ".github/workflows/release-candidate.yml",
  "README.md", "README.zh-CN.md", "QUICKSTART.md", "QUICKSTART.zh-CN.md",
  "docs/COMPATIBILITY.md", "docs/zh-CN/COMPATIBILITY.md", "docs/RELEASE_NOTES.md", "docs/zh-CN/RELEASE_NOTES.md",
  "docs/RELEASE_READINESS.md", "docs/zh-CN/RELEASE_READINESS.md", "docs/PUBLIC_RELEASE.md", "docs/zh-CN/PUBLIC_RELEASE.md",
  "config/compatibility-matrix.json", "config/sbom.json", "config/third-party-lock.json", "config/public-release-files.txt"
)
foreach ($Path in $RequiredPaths) {
  if (-not (Test-Path -LiteralPath (Join-Path $Repo $Path) -PathType Leaf)) { throw "missing public closeout path: $Path" }
}
Get-ChildItem -LiteralPath $Repo -Filter "*.md" -File -Recurse | ForEach-Object {
  $Text = [System.IO.File]::ReadAllText($_.FullName)
  foreach ($Match in [regex]::Matches($Text, '\[[^\]]+\]\(([^)#]+)(?:#[^)]+)?\)')) {
    $Target = $Match.Groups[1].Value
    if ($Target -match '^(?:https?://|mailto:|#)') { continue }
    $Resolved = Join-Path $_.DirectoryName ($Target -replace '/', '\')
    if (-not (Test-Path -LiteralPath $Resolved)) { throw "broken documentation link: $($_.FullName) -> $Target" }
  }
}
if (Test-Path -LiteralPath (Join-Path $Repo ".github\FUNDING.yml")) { throw "unexpected funding configuration" }
Write-Host "public_closeout_structure_state=ready"
Write-Host "local_verification_state=ready"
