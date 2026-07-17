param([string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path)
$ErrorActionPreference = "Stop"
$Deploy = Join-Path $Repo "scripts\deploy-merlin.ps1"
$Plan = & powershell -NoProfile -ExecutionPolicy Bypass -File $Deploy -Router user@router 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $Plan -notmatch 'deploy_state=plan') { throw "PowerShell deploy plan failed" }
$Source = Get-Content -LiteralPath $Deploy -Raw
if ($Source -notmatch 'new-deployment-provenance\.ps1') { throw "PowerShell deploy does not generate provenance from staged bytes" }
if ($Source -notmatch 'DEPLOYMENT-CONTENT-SHA256SUMS') { throw "PowerShell deploy lacks provenance archive contract" }
if ($Source -notmatch '/jffs/home-edge-bootstrap-state/lifecycle/state\.env') { throw "PowerShell deploy does not verify stable state schema" }
if ($Source -notmatch 'stable_state_root=/jffs/home-edge-bootstrap-state') { throw "PowerShell deploy does not verify stable state root metadata" }
Write-Host "deploy_fixture_tests_ps=ok"
