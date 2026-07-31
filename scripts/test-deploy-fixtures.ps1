param([string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path)
$ErrorActionPreference = "Stop"
$Deploy = Join-Path $Repo "scripts\deploy-merlin.ps1"
$Plan = & powershell -NoProfile -ExecutionPolicy Bypass -File $Deploy -Router user@router 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $Plan -notmatch 'deploy_state=plan') { throw "PowerShell deploy plan failed" }
$FixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("home-edge-deploy-ps-" + [guid]::NewGuid().ToString("N"))
$FixtureBundle = Join-Path $FixtureRoot "bundle"
$PreviousBundleDir = $env:DEPLOY_BUNDLE_DIR
try {
  New-Item -ItemType Directory -Force -Path $FixtureBundle | Out-Null
  [System.IO.File]::WriteAllBytes(
    (Join-Path $FixtureBundle "mihomo-linux-arm64"),
    [byte[]](0x7f, 0x45, 0x4c, 0x46, 0x0a)
  )
  Set-Content -LiteralPath (Join-Path $FixtureBundle "ShellCrash.tar.gz") -Value "fixture" -NoNewline
  Set-Content -LiteralPath (Join-Path $FixtureBundle "MANIFEST.json") -Value '{"schema":1}' -NoNewline
  $ChecksumLines = foreach ($Name in @("mihomo-linux-arm64", "ShellCrash.tar.gz")) {
    $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $FixtureBundle $Name)).Hash.ToLowerInvariant()
    "$Hash  $Name"
  }
  Set-Content -LiteralPath (Join-Path $FixtureBundle "SHA256SUMS") -Value $ChecksumLines
  $env:DEPLOY_BUNDLE_DIR = $FixtureBundle
  $RuntimePlan = & powershell -NoProfile -ExecutionPolicy Bypass -File $Deploy -Router user@router -InstallRuntime 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0 -or $RuntimePlan -notmatch '(?m)^include_bundle=0\r?$') { throw "PowerShell runtime plan persists the bundle in JFFS" }
  if ($RuntimePlan -notmatch '(?m)^runtime_bundle_transport=temporary\r?$') { throw "PowerShell runtime plan does not disclose temporary bundle transport" }
} finally {
  $env:DEPLOY_BUNDLE_DIR = $PreviousBundleDir
  Remove-Item -LiteralPath $FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
$Source = Get-Content -LiteralPath $Deploy -Raw
if ($Source -notmatch 'DEPLOY_BUNDLE_DIR') { throw "PowerShell deploy lacks a temporary bundle override for fixture and offline use" }
if ($Source -notmatch 'new-deployment-provenance\.ps1') { throw "PowerShell deploy does not generate provenance from staged bytes" }
if ($Source -notmatch 'DEPLOYMENT-CONTENT-SHA256SUMS') { throw "PowerShell deploy lacks provenance archive contract" }
if ($Source -notmatch '/jffs/home-edge-bootstrap-state/lifecycle/state\.env') { throw "PowerShell deploy does not verify stable state schema" }
if ($Source -notmatch 'stable_state_root=/jffs/home-edge-bootstrap-state') { throw "PowerShell deploy does not verify stable state root metadata" }
if ($Source -notmatch 'cleanup_first_install_active_state') { throw "PowerShell deploy does not clean first-install active surfaces on rollback" }
if ($Source -notmatch 'home-edge-start-shellcrash\.sh\s+\\\s+home-edge-configure-service-rules\.sh') {
  throw "PowerShell deploy cleanup list does not include the service-rules helper safely"
}
if ($Source -notmatch 'BOOTSTRAP_BUNDLE_DIR') { throw "PowerShell deploy does not bind a temporary runtime bundle directory" }
if ($Source -notmatch 'BOOTSTRAP_RUNTIME_FOLLOWS=1') { throw "PowerShell deploy does not declare its two-stage runtime continuation" }
if ($Source -notmatch 'deploy_state=staged') { throw "PowerShell deploy does not stage the control plane before runtime activation" }
if ($Source -notmatch 'control_plane_rollback_state=restored') { throw "PowerShell deploy lacks previous control-plane restoration after runtime failure" }
if ($Source -notmatch 'control_plane_rollback_state=removed') { throw "PowerShell deploy lacks first-install staged control-plane cleanup after runtime failure" }
if ($Source -notmatch 'RuntimeRollbackRemote') { throw "PowerShell deploy does not invoke a separate runtime-failure rollback" }
if ($Source -notmatch '(?s)\$RuntimeRollbackTemplate\s*=\s*@''.*cleanup_first_install_active_state') {
  throw "PowerShell runtime-failure rollback does not clean first-install active surfaces"
}
if ($Source -notmatch '(?s)\$RuntimeRollbackTemplate\s*=\s*@''.*HOME_EDGE_WRITE_LOCK_HELD=1 BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 sh "\$remote_dir/bootstrap\.sh"') {
  throw "PowerShell runtime-failure rollback does not replay the restored control plane"
}
if ($Source -notmatch 'RuntimePayloadBytes \* 2') { throw "PowerShell deploy does not derive conservative space from host bundle size" }
if ($Source -notmatch 'LC_ALL=C df -k /tmp') { throw "PowerShell deploy lacks portable remote /tmp space inspection" }
if ($Source -notmatch 'runtime_space_preflight_state=ready') { throw "PowerShell deploy lacks a ready space marker" }
if ($Source -notmatch 'runtime_space_preflight_state=insufficient') { throw "PowerShell deploy lacks an insufficient space marker" }
if ($Source.IndexOf('$RuntimeSpaceRemote') -gt $Source.IndexOf('New-Item -ItemType Directory -Force $Stage')) { throw "PowerShell space preflight occurs after deployment staging" }
if ($Source -notmatch 'openssl base64 -d -A') { throw "PowerShell deploy lacks a Merlin-compatible base64 decoder fallback" }
if ($Source -notmatch "tr -cd 'A-Za-z0-9\+/='") { throw "PowerShell deploy does not normalize BOM/CRLF-contaminated base64 input" }
if ($Source -match 'command -v') { throw "PowerShell remote deploy must not depend on command -v" }
Write-Host "deploy_fixture_tests_ps=ok"
