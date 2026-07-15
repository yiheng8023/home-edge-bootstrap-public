param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

$GuideFixture = @"
device_state=ssh_reachable
baseline_state=reviewed_with_monitoring
proxy_state=verified
runtime_state=running
controller_state=reachable
controller_auth_state=authenticated
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
subscription_consumption_state=runtime_profile_matches_cache
automation_state=live_managed
risk_count=0
review_count=0
monitor_count=1
"@

$ClientFixture = @"
client_topology_mode=hybrid
client_runtime_present=1
client_conflict_risk=medium
gateway_matches_router=yes
client_http_state=ok:204
"@

$env:EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT = $GuideFixture
$env:EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT = $ClientFixture

try {
  $Output = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\check-edge-health.ps1") -Router "user@192.168.50.1" -Json | Out-String
}
finally {
  Remove-Item Env:\EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item Env:\EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT -ErrorAction SilentlyContinue
}

$Summary = $Output | ConvertFrom-Json

if ($Summary.edge_health_state -ne "router_managed") { throw "expected edge_health_state=router_managed got=$($Summary.edge_health_state)" }
if ($Summary.proxy_state -ne "verified") { throw "expected proxy_state=verified got=$($Summary.proxy_state)" }
if ($Summary.subscription_state -ne "cache_ready") { throw "expected subscription_state=cache_ready got=$($Summary.subscription_state)" }
if ($Summary.client_topology_mode -ne "hybrid") { throw "expected client_topology_mode=hybrid got=$($Summary.client_topology_mode)" }
if ($Summary.client_conflict_risk -ne "medium") { throw "expected client_conflict_risk=medium got=$($Summary.client_conflict_risk)" }
if ($Summary.next_action -ne "none") { throw "expected next_action=none got=$($Summary.next_action)" }

$UnknownClientFixture = @"
client_topology_mode=unknown
client_runtime_present=unknown
client_conflict_risk=unknown
gateway_matches_router=yes
client_http_state=ok:204
"@
$env:EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT = $GuideFixture
$env:EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT = $UnknownClientFixture
try {
  $UnknownOutput = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\check-edge-health.ps1") -Router "user@192.168.50.1" -Json | Out-String
}
finally {
  Remove-Item Env:\EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item Env:\EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT -ErrorAction SilentlyContinue
}
$UnknownSummary = $UnknownOutput | ConvertFrom-Json
if ($UnknownSummary.client_topology_mode -ne "unknown") { throw "expected unknown client_topology_mode to pass through" }
if ($UnknownSummary.client_runtime_present -ne "unknown") { throw "expected unknown client_runtime_present to pass through" }
if ($UnknownSummary.client_conflict_risk -ne "unknown") { throw "expected unknown client_conflict_risk to pass through" }

$RegistrationGuide = @"
device_state=ssh_reachable
baseline_state=reviewed_with_monitoring
proxy_state=verified
runtime_state=running
controller_state=reachable
controller_auth_state=authenticated
self_heal_registration_state=missing
self_heal_boot_hook_state=missing
subscription_state=cache_ready
subscription_consumption_state=cache_only_unverified
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1
"@
$env:EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT = $RegistrationGuide
$env:EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT = $ClientFixture
try {
  $RegistrationSummary = (powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\check-edge-health.ps1") -Router "user@192.168.50.1" -Json | Out-String) | ConvertFrom-Json
}
finally {
  Remove-Item Env:\EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item Env:\EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT -ErrorAction SilentlyContinue
}
if ($RegistrationSummary.edge_health_state -ne "lifecycle_registration_degraded") { throw "expected lifecycle_registration_degraded" }

$AuthGuide = @"
device_state=ssh_reachable
baseline_state=reviewed_with_monitoring
proxy_state=policy_deployed
runtime_state=authentication_blocked
controller_state=reachable
controller_auth_state=required_or_failed
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
subscription_consumption_state=cache_only_unverified
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1
"@
$env:EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT = $AuthGuide
$env:EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT = $ClientFixture
try {
  $AuthSummary = (powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\check-edge-health.ps1") -Router "user@192.168.50.1" -Json | Out-String) | ConvertFrom-Json
}
finally {
  Remove-Item Env:\EDGE_HEALTH_FIXTURE_GUIDE_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item Env:\EDGE_HEALTH_FIXTURE_CLIENT_OUTPUT -ErrorAction SilentlyContinue
}
if ($AuthSummary.edge_health_state -ne "controller_auth_blocked") { throw "expected controller_auth_blocked" }

Write-Host "edge_health_fixture_tests=ok"
