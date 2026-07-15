param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

$env:DOCTOR_FIXTURE_REPOSITORY_OUTPUT = "closeout_state=ready"
$env:DOCTOR_FIXTURE_NO_WALL_OUTPUT = "status=tools_ready`nbundle_state=verified"
$env:DOCTOR_FIXTURE_HOST_SSH_OUTPUT = "host_ssh_check_state=ready`nrouter_ssh_state=ok`nssh_failure_hint=unknown"
$env:DOCTOR_FIXTURE_EDGE_HEALTH_OUTPUT = @"
edge_health_state=router_managed
proxy_state=verified
subscription_state=cache_ready
automation_state=live_managed
client_topology_mode=hybrid
client_runtime_present=1
client_conflict_risk=medium
next_action=none
"@

try {
  $Output = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\doctor.ps1") -Router "user@192.168.50.1" -Json | Out-String
}
finally {
  Remove-Item Env:\DOCTOR_FIXTURE_REPOSITORY_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item Env:\DOCTOR_FIXTURE_NO_WALL_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item Env:\DOCTOR_FIXTURE_HOST_SSH_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item Env:\DOCTOR_FIXTURE_EDGE_HEALTH_OUTPUT -ErrorAction SilentlyContinue
}

$Summary = $Output | ConvertFrom-Json

if ($Summary.doctor_state -ne "ready") { throw "expected doctor_state=ready got=$($Summary.doctor_state)" }
if ($Summary.repository_state -ne "ready") { throw "expected repository_state=ready got=$($Summary.repository_state)" }
if ($Summary.working_directory_state -notin @("repo_root", "inside_repo", "outside_repo")) { throw "unexpected working_directory_state=$($Summary.working_directory_state)" }
if ($Summary.local_tools_state -ne "tools_ready") { throw "expected local_tools_state=tools_ready got=$($Summary.local_tools_state)" }
if ($Summary.host_ssh_check_state -ne "ready") { throw "expected host_ssh_check_state=ready got=$($Summary.host_ssh_check_state)" }
if ($Summary.edge_health_state -ne "router_managed") { throw "expected edge_health_state=router_managed got=$($Summary.edge_health_state)" }
if ($Summary.client_topology_mode -ne "hybrid") { throw "expected client_topology_mode=hybrid got=$($Summary.client_topology_mode)" }
if ($Summary.next_action -ne "none") { throw "expected next_action=none got=$($Summary.next_action)" }

Write-Host "doctor_fixture_tests=ok"
