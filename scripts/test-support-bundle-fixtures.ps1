param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

$OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) ("home-edge-support-fixture-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$env:CLIENT_TOPOLOGY_FIXTURE_OS = "windows"
$env:CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY = "192.168.50.1"
$env:CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE = "unknown"
$env:CLIENT_TOPOLOGY_FIXTURE_TUN_STATE = "unknown"
$env:CLIENT_TOPOLOGY_FIXTURE_DNS_STATE = "unknown"
$env:CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE = "ok:204"
$env:HOST_SSH_FIXTURE_AGENT_STATE = "identities_loaded"
$env:HOST_SSH_FIXTURE_DEFAULT_KEY_STATE = "present"
$env:HOST_SSH_FIXTURE_ROUTER_SSH_STATE = "ok"

try {
  $Output = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\export-support-bundle.ps1") -Repo $Repo -OutputDir $OutputDir | Out-String
  $BundleDir = ($Output -split "`r?`n" | Where-Object { $_ -like "support_bundle_dir=*" } | Select-Object -First 1) -replace "^support_bundle_dir=", ""
  if (-not $BundleDir -or -not (Test-Path -LiteralPath $BundleDir -PathType Container)) {
    throw "support bundle directory was not created"
  }

  foreach ($Name in @("manifest.txt", "closeout.txt", "no-wall-readiness.txt", "doctor.txt", "host-ssh.txt", "client-topology.txt", "edge-health.txt", "router-status.txt")) {
    if (-not (Test-Path -LiteralPath (Join-Path $BundleDir $Name) -PathType Leaf)) {
      throw "missing support bundle file: $Name"
    }
  }

  $RawFiles = Get-ChildItem -LiteralPath $BundleDir -Recurse -File | Where-Object { $_.Name -like "*.raw" -or $_.Name -like "*.raw.log" }
  if ($RawFiles.Count -gt 0) {
    throw "raw support files were left behind"
  }

  $ClientTopology = Get-Content -LiteralPath (Join-Path $BundleDir "client-topology.txt") -Raw
  if ($ClientTopology -notmatch "(?m)^client_runtime_present=unknown$") {
    throw "support bundle did not preserve unknown client runtime evidence"
  }

  & (Join-Path $Repo "scripts\scan-secrets.ps1") -Repo $Repo -ScanPath $BundleDir | Out-Null
}
finally {
  Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_OS -ErrorAction SilentlyContinue
  Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_DEFAULT_GATEWAY -ErrorAction SilentlyContinue
  Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_PROXY_STATE -ErrorAction SilentlyContinue
  Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_TUN_STATE -ErrorAction SilentlyContinue
  Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_DNS_STATE -ErrorAction SilentlyContinue
  Remove-Item Env:\CLIENT_TOPOLOGY_FIXTURE_HTTP_STATE -ErrorAction SilentlyContinue
  Remove-Item Env:\HOST_SSH_FIXTURE_AGENT_STATE -ErrorAction SilentlyContinue
  Remove-Item Env:\HOST_SSH_FIXTURE_DEFAULT_KEY_STATE -ErrorAction SilentlyContinue
  Remove-Item Env:\HOST_SSH_FIXTURE_ROUTER_SSH_STATE -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $OutputDir -PathType Container) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
  }
}

Write-Host "support_bundle_fixture_tests=ok"
