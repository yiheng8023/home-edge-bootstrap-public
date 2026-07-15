param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

function Invoke-Case {
  param(
    [string]$Name,
    [string]$AuditFixture,
    [string]$ExpectedCode
  )

  $CaseRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("home-edge-guide-router-fixture-$PID-$Name")
  $AuditLogPath = Join-Path $CaseRoot "audit.log"
  $KnownHostsFile = Join-Path $CaseRoot "known_hosts"
  $env:GUIDE_ROUTER_FIXTURE_AUDIT_OUTPUT = $AuditFixture
  try {
    $Output = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\guide-router.ps1") -Router "user@192.168.50.1" -AuditLogPath $AuditLogPath -KnownHostsFile $KnownHostsFile -Json | Out-String
  }
  finally {
    Remove-Item Env:\GUIDE_ROUTER_FIXTURE_AUDIT_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $CaseRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  $Summary = $Output | ConvertFrom-Json
  if ($Summary.next_action_code -ne $ExpectedCode) {
    throw "$Name expected next_action_code=$ExpectedCode got=$($Summary.next_action_code)"
  }
  if (-not $Summary.next_action_command) {
    throw "$Name expected next_action_command"
  }
}

Invoke-Case missing_prereqs @"
device_state=ssh_reachable
firmware_state=official_merlin
admin_state=ssh_reachable
baseline_state=reviewed
proxy_state=absent
subscription_state=missing
automation_state=audit_only
risk_count=0
review_count=0
monitor_count=0
"@ enable_router_prereqs

Invoke-Case deploy_plan @"
device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed
proxy_state=absent
subscription_state=missing
automation_state=apply_ready
risk_count=0
review_count=0
monitor_count=0
"@ deploy_plan

Invoke-Case enable_live_self_heal @"
device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed_with_monitoring
proxy_state=verified
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1
"@ enable_live_self_heal

Invoke-Case repair_self_heal_registration @"
device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed_with_monitoring
proxy_state=verified
self_heal_registration_state=missing
self_heal_boot_hook_state=missing
subscription_state=cache_ready
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1
"@ repair_self_heal_registration

Invoke-Case deploy_pre_lifecycle_installation @"
device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed_with_monitoring
proxy_state=verified
lifecycle_reconciler_state=absent
self_heal_registration_state=missing
self_heal_boot_hook_state=missing
subscription_state=cache_ready
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1
"@ deploy_plan

Invoke-Case configure_controller_auth @"
device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
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
"@ configure_controller_auth

Invoke-Case inspect_or_start_proxy_runtime @"
device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed_with_monitoring
proxy_state=policy_deployed
runtime_state=controller_unreachable
controller_state=unreachable
controller_auth_state=unknown
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
subscription_consumption_state=cache_only_unverified
automation_state=dry_run_ready
risk_count=0
review_count=0
monitor_count=1
"@ inspect_or_start_proxy_runtime

Invoke-Case monitor_live_managed @"
device_state=ssh_reachable
firmware_state=official_merlin
admin_state=jffs_scripts_ready
baseline_state=reviewed_with_monitoring
proxy_state=verified
self_heal_registration_state=ready
self_heal_boot_hook_state=ready
subscription_state=cache_ready
automation_state=live_managed
risk_count=0
review_count=0
monitor_count=1
"@ monitor_live_managed

Write-Host "guide_router_fixture_tests=ok"
