param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$Path = Join-Path $Repo "config\compatibility-matrix.json"
$Failures = New-Object System.Collections.Generic.List[string]

function Fail([string]$Message) { $Failures.Add($Message) | Out-Null }

function Assert-ExactPropertySet($Object, [string[]]$Expected, [string]$Label) {
  if ($null -eq $Object) { Fail "missing_object=$Label"; return }
  $Actual = @($Object.PSObject.Properties.Name | Sort-Object)
  $Wanted = @($Expected | Sort-Object)
  if (($Actual -join "`n") -cne ($Wanted -join "`n")) { Fail "invalid_property_set=$Label" }
}

function Assert-StringArrayExact($Value, [string[]]$Expected, [string]$Label) {
  if (-not ($Value -is [System.Array])) { Fail "invalid_array_type=$Label"; return }
  $Actual = @($Value)
  if (@($Actual | Where-Object { -not ($_ -is [string]) }).Count -ne 0) { Fail "invalid_array_item_type=$Label"; return }
  if (($Actual -join "`n") -cne ($Expected -join "`n")) { Fail "invalid_array_value=$Label" }
}

$Policy = $null
$PolicyParsed = $false
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
  Fail "missing_file=config/compatibility-matrix.json"
}
else {
  try {
    $Policy = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $PolicyParsed = $true
  }
  catch { Fail "invalid_json=config/compatibility-matrix.json" }
}

if ($PolicyParsed -and -not ($Policy -is [pscustomobject])) {
  Fail "invalid_root_type"
}

if ($Policy -is [pscustomobject]) {
  Assert-ExactPropertySet $Policy @(
    "schema_version", "format", "authority_boundary", "certification_policy",
    "adapter_maturity_model", "capability_requirements", "support_levels",
    "declared_targets", "field_evidence"
  ) "root"

  if ((-not ($Policy.schema_version -is [int]) -and -not ($Policy.schema_version -is [long])) -or $Policy.schema_version -ne 1) { Fail "invalid_schema_version" }
  if (-not ($Policy.format -is [string]) -or $Policy.format -cne "home-edge-public-compatibility/v1") { Fail "invalid_format" }
  if (-not ($Policy.authority_boundary -is [string]) -or [string]$Policy.authority_boundary -notmatch "policy inputs, not observations") { Fail "invalid_authority_boundary" }
  if (-not ($Policy.certification_policy -is [string]) -or [string]$Policy.certification_policy -notmatch "fixtures are not field certification") { Fail "missing_fixture_certification_boundary" }
  if (-not ($Policy.field_evidence -is [System.Array]) -or @($Policy.field_evidence).Count -ne 0) { Fail "field_evidence_must_be_empty" }

  $Maturity = $Policy.adapter_maturity_model
  Assert-ExactPropertySet $Maturity @("independent_from_target_support", "stages", "current_reference") "adapter_maturity_model"
  if (-not ($Maturity.independent_from_target_support -is [bool]) -or $Maturity.independent_from_target_support -ne $true) { Fail "adapter_maturity_support_boundary_missing" }
  Assert-StringArrayExact $Maturity.stages @(
    "external-integration", "experimental-adapter", "community-maintained-adapter", "verified-adapter"
  ) "adapter_maturity_model.stages"
  $Reference = $Maturity.current_reference
  Assert-ExactPropertySet $Reference @("id", "role", "assigned_stage", "claim_boundary") "adapter_maturity_model.current_reference"
  if (-not ($Reference.id -is [string]) -or $Reference.id -cne "merlin") { Fail "invalid_current_reference_id" }
  if (-not ($Reference.role -is [string]) -or $Reference.role -cne "implemented-reference") { Fail "invalid_current_reference_role" }
  if ($null -ne $Reference.assigned_stage) { Fail "current_reference_stage_must_be_null" }
  if (-not ($Reference.claim_boundary -is [string]) -or [string]$Reference.claim_boundary -cne "Reference status does not assign a verified maturity stage.") { Fail "invalid_current_reference_boundary" }

  $ExpectedRequirements = @(
    [ordered]@{ id = "host-guided-shell"; description = "Windows PowerShell 5.1+ or a POSIX sh host on macOS/Linux with SSH, archive tools, and Python 3 available as python3 or as python pointing to Python 3"; required_for = @("guided-flow", "local-verification") },
    [ordered]@{ id = "official-asuswrt-merlin-router"; description = "ASUS gateway running official Asuswrt-Merlin with SSH, persistent /jffs storage, and required POSIX utilities"; required_for = @("router-bootstrap", "router-recovery") },
    [ordered]@{ id = "shellcrash-mihomo-runtime"; description = "ShellCrash/ShellClash with a Mihomo-compatible runtime and a discoverable health or controller surface"; required_for = @("router-bootstrap", "router-recovery") },
    [ordered]@{ id = "supported-runtime-architecture"; description = "A runtime payload and CPU architecture combination declared by the concrete offline release artifact"; required_for = @("fresh-offline-runtime-install") },
    [ordered]@{ id = "independent-fallback"; description = "A separately managed soft-router or endpoint path for recovery access"; required_for = @("recommended-safe-apply") }
  )
  if (-not ($Policy.capability_requirements -is [System.Array])) { Fail "invalid_array_type=capability_requirements" }
  $Requirements = @($Policy.capability_requirements)
  if ($Requirements.Count -ne $ExpectedRequirements.Count) { Fail "invalid_capability_requirement_count" }
  for ($Index = 0; $Index -lt [Math]::Min($Requirements.Count, $ExpectedRequirements.Count); $Index++) {
    $Actual = $Requirements[$Index]; $Expected = $ExpectedRequirements[$Index]
    Assert-ExactPropertySet $Actual @("id", "description", "required_for") "capability_requirements[$Index]"
    if (-not ($Actual.id -is [string]) -or $Actual.id -cne $Expected.id) { Fail "invalid_capability_requirement_id=$Index" }
    if (-not ($Actual.description -is [string]) -or $Actual.description -cne $Expected.description) { Fail "invalid_capability_requirement_description=$Index" }
    Assert-StringArrayExact $Actual.required_for $Expected.required_for "capability_requirements[$Index].required_for"
  }

  $ExpectedLevels = @(
    [ordered]@{ id = "supported"; meaning = "All required capabilities and applicable evidence gates are satisfied for the evaluated target." },
    [ordered]@{ id = "supported_needs_manual"; meaning = "The target is suitable, but a named manual action must be completed before automation proceeds." },
    [ordered]@{ id = "accepted_modified"; meaning = "The operator explicitly accepts a compatible modified baseline and its provenance and support risk." },
    [ordered]@{ id = "unknown"; meaning = "Evidence is insufficient to determine one or more required target capabilities; do not apply." },
    [ordered]@{ id = "unsupported"; meaning = "A required capability is absent or conflicts with the documented boundary; do not apply." }
  )
  if (-not ($Policy.support_levels -is [System.Array])) { Fail "invalid_array_type=support_levels" }
  $Levels = @($Policy.support_levels)
  if ($Levels.Count -ne $ExpectedLevels.Count) { Fail "invalid_support_level_count" }
  for ($Index = 0; $Index -lt [Math]::Min($Levels.Count, $ExpectedLevels.Count); $Index++) {
    $Actual = $Levels[$Index]; $Expected = $ExpectedLevels[$Index]
    Assert-ExactPropertySet $Actual @("id", "meaning") "support_levels[$Index]"
    if (-not ($Actual.id -is [string]) -or $Actual.id -cne $Expected.id) { Fail "invalid_support_level_id=$Index" }
    if (-not ($Actual.meaning -is [string]) -or $Actual.meaning -cne $Expected.meaning) { Fail "invalid_support_level_meaning=$Index" }
  }

  if (-not ($Policy.declared_targets -is [System.Array])) { Fail "invalid_array_type=declared_targets" }
  $Targets = @($Policy.declared_targets)
  if ($Targets.Count -ne 2) { Fail "invalid_declared_target_count" }
  if ($Targets.Count -ge 1) {
    $Router = $Targets[0]
    Assert-ExactPropertySet $Router @("path", "adapter_id", "adapter_role", "platform", "runtime", "support_level", "classification_basis") "declared_targets[0]"
    $RouterTypesValid =
      ($Router.path -is [string]) -and
      ($Router.adapter_id -is [string]) -and
      ($Router.adapter_role -is [string]) -and
      ($Router.platform -is [string]) -and
      ($Router.runtime -is [string]) -and
      ($Router.support_level -is [string]) -and
      ($Router.classification_basis -is [string])
    if (-not $RouterTypesValid -or $Router.path -cne "router" -or $Router.adapter_id -cne "merlin" -or $Router.adapter_role -cne "implemented-reference" -or $Router.platform -cne "ASUS gateway running official Asuswrt-Merlin" -or $Router.runtime -cne "ShellCrash/ShellClash with a Mihomo-compatible runtime" -or $Router.support_level -cne "unknown" -or $Router.classification_basis -cne "No target-specific field evidence is published; run read-only target capability checks.") { Fail "invalid_router_target_classification" }
  }
  if ($Targets.Count -ge 2) {
    $Fallback = $Targets[1]
    Assert-ExactPropertySet $Fallback @("path", "adapter_id", "adapter_role", "platform", "runtime", "support_level", "classification_basis") "declared_targets[1]"
    $FallbackTypesValid =
      ($Fallback.path -is [string]) -and
      ($null -eq $Fallback.adapter_id) -and
      ($Fallback.adapter_role -is [string]) -and
      ($Fallback.platform -is [string]) -and
      ($Fallback.runtime -is [string]) -and
      ($Fallback.support_level -is [string]) -and
      ($Fallback.classification_basis -is [string])
    if (-not $FallbackTypesValid -or $Fallback.path -cne "soft-router-or-endpoint-fallback" -or $Fallback.adapter_role -cne "independent-fallback" -or $Fallback.platform -cne "independently managed soft router or endpoint" -or $Fallback.runtime -cne "managed outside this adapter framework" -or $Fallback.support_level -cne "unknown" -or $Fallback.classification_basis -cne "The fallback is independently managed and does not provide evidence for the router path.") { Fail "invalid_fallback_target_classification" }
  }
  $LevelIds = @($Levels | ForEach-Object { [string]$_.id })
  foreach ($Target in $Targets) {
    if (-not ($Target.support_level -is [string]) -or $LevelIds -cnotcontains [string]$Target.support_level) { Fail "unknown_target_support_level=$([string]$Target.path)" }
  }
}

if ($Failures.Count) {
  Write-Host "compatibility_policy_state=failed"
  $Failures | ForEach-Object { Write-Host "compatibility_policy_failure=$_" }
  exit 1
}

Write-Host "compatibility_policy_state=ready"
Write-Host "compatibility_field_evidence_count=0"
Write-Host "compatibility_capability_requirement_count=5"
Write-Host "compatibility_support_level_count=5"
Write-Host "compatibility_declared_target_count=2"
