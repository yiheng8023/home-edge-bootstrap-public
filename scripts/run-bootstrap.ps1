param(
  [string]$Router = $env:ROUTER,
  [string]$SessionDir = "",
  [int]$MaxLoops = 20,
  [switch]$ApplyDeploy,
  [switch]$EnableLiveSelfHeal,
  [switch]$AcceptRuntimeImportedSubscription,
  [switch]$DashboardConfirmed,
  [switch]$AcceptClientRuntime,
  [switch]$ClientConfirmed,
  [switch]$RunClientCheck,
  [switch]$NoPause
)

$ErrorActionPreference = "Stop"

if (-not $Router) {
  throw "Router is required. Pass -Router <ssh-user>@<router-ip> or set ROUTER."
}

$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RouterId = ($Router -replace '[^A-Za-z0-9_.-]', '_')
if (-not $SessionDir) {
  $SessionDir = Join-Path $Repo (Join-Path "logs\bootstrap" $RouterId)
}
$SessionDir = [System.IO.Path]::GetFullPath($SessionDir)
$SessionRoot = [System.IO.Path]::GetPathRoot($SessionDir)
if ($SessionDir -eq $SessionRoot) {
  throw "Unsafe bootstrap session directory: $SessionDir"
}
$LogDir = Join-Path $SessionDir "logs"
$ScratchDir = Join-Path $SessionDir "scratch"
$ScratchMarker = Join-Path $ScratchDir ".home-edge-bootstrap-scratch"
$StatePath = Join-Path $SessionDir "state.json"
$MainLog = Join-Path $LogDir "bootstrap.log"
$KnownHostsFile = Join-Path $SessionDir "known_hosts"
$LockDir = Join-Path $SessionDir ".bootstrap.lock"
$LockHeld = $false
$LogMaxBytes = 2097152L
if ($env:BOOTSTRAP_LOG_MAX_BYTES) {
  $ParsedLogMaxBytes = 0L
  if ([int64]::TryParse($env:BOOTSTRAP_LOG_MAX_BYTES, [ref]$ParsedLogMaxBytes) -and $ParsedLogMaxBytes -gt 0) {
    $LogMaxBytes = $ParsedLogMaxBytes
  }
}
$GuideAuditLog = Join-Path $LogDir "router-guide-audit.log"
$RouterStatusLog = Join-Path $LogDir "router-status.log"

New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
if ((Test-Path -LiteralPath $ScratchDir) -and -not (Test-Path -LiteralPath $ScratchDir -PathType Container)) {
  throw "Bootstrap scratch path is not a directory: $ScratchDir"
}
if ((Test-Path -LiteralPath $ScratchDir -PathType Container) -and -not (Test-Path -LiteralPath $ScratchMarker -PathType Leaf)) {
  throw "Refusing to reuse unowned scratch directory: $ScratchDir"
}
New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null
Set-Content -LiteralPath $ScratchMarker -Value "owned_by=home-edge-bootstrap" -Encoding ASCII
if ((Test-Path -LiteralPath $MainLog) -and (Get-Item -LiteralPath $MainLog).Length -gt $LogMaxBytes) {
  Move-Item -LiteralPath $MainLog -Destination "$MainLog.1" -Force
}


function Now-Iso { (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK") }

function Write-FlowLog {
  param([string]$Level, [string]$Message)
  $Line = "$(Now-Iso) [$Level] $Message"
  Add-Content -LiteralPath $MainLog -Value $Line -Encoding UTF8
  Write-Host $Line
}

function Save-State {
  param(
    [string]$State,
    [string]$Phase,
    [string]$NextActionCode = "",
    [string]$NextActionCommand = ""
  )
  $Payload = [ordered]@{
    bootstrap_state = $State
    phase = $Phase
    router = $Router
    session_dir = $SessionDir
    log_dir = $LogDir
    next_action_code = $NextActionCode
    next_action_command = $NextActionCommand
    known_hosts_file = $KnownHostsFile
    updated_at = (Now-Iso)
  }
  $StateTempPath = "$StatePath.tmp"
  $Payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StateTempPath -Encoding UTF8
  Move-Item -LiteralPath $StateTempPath -Destination $StatePath -Force
}

function Get-StateValue {
  param([string]$Text, [string]$Key)
  $Match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Key))=(.+)$")
  if ($Match.Success) { return $Match.Groups[1].Value.Trim() }
  return ""
}

function Run-Step {
  param(
    [string]$Name,
    [scriptblock]$Block,
    [switch]$AllowFailure
  )
  $StepLog = Join-Path $LogDir "$Name.log"
  Write-FlowLog "INFO" "step_start=$Name log=$StepLog"
  if ($env:BOOTSTRAP_TEST_MODE -eq "1") {
    "BOOTSTRAP_TEST_MODE skipped step: $Name" | Set-Content -LiteralPath $StepLog -Encoding UTF8
    Write-FlowLog "INFO" "step_skipped_test_mode=$Name"
    return [ordered]@{ ExitCode = 0; Output = "BOOTSTRAP_TEST_MODE skipped step: $Name"; LogPath = $StepLog }
  }

  $global:LASTEXITCODE = 0
  $Output = & $Block 2>&1 | Out-String
  $Output | Set-Content -LiteralPath $StepLog -Encoding UTF8
  $ExitCode = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 0 }
  if ($ExitCode -ne 0 -and -not $AllowFailure) {
    Write-FlowLog "ERROR" "step_failed=$Name exit_code=$ExitCode"
    Save-State "failed" $Name
    throw "$Name failed with exit code $ExitCode. See $StepLog"
  }
  Write-FlowLog "INFO" "step_end=$Name exit_code=$ExitCode"
  return [ordered]@{ ExitCode = $ExitCode; Output = $Output; LogPath = $StepLog }
}

function Invoke-Guide {
  if ($env:BOOTSTRAP_FIXTURE_GUIDE_JSON) {
    Write-FlowLog "INFO" "using_fixture=guide"
    return ($env:BOOTSTRAP_FIXTURE_GUIDE_JSON | ConvertFrom-Json)
  }
  $Guide = Run-Step "guide-router" {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "guide-router.ps1") -Router $Router -AuditLogPath $GuideAuditLog -KnownHostsFile $KnownHostsFile -Json
  }
  return ($Guide.Output | ConvertFrom-Json)
}

function Invoke-Closeout {
  if ($env:BOOTSTRAP_FIXTURE_CLOSEOUT_OUTPUT) {
    Write-FlowLog "INFO" "using_fixture=installation_closeout"
    $FixtureExit = 0
    if ($env:BOOTSTRAP_FIXTURE_CLOSEOUT_EXIT) { $FixtureExit = [int]$env:BOOTSTRAP_FIXTURE_CLOSEOUT_EXIT }
    return [ordered]@{ ExitCode = $FixtureExit; Output = $env:BOOTSTRAP_FIXTURE_CLOSEOUT_OUTPUT; LogPath = Join-Path $LogDir "installation-closeout.log" }
  }
  $CloseoutArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "check-installation-closeout.ps1"), "-Router", $Router, "-Repo", $Repo)
  if ($AcceptRuntimeImportedSubscription) { $CloseoutArgs += "-AcceptRuntimeImportedSubscription" }
  if ($DashboardConfirmed) { $CloseoutArgs += "-DashboardConfirmed" }
  if ($AcceptClientRuntime) { $CloseoutArgs += "-AcceptClientRuntime" }
  if ($ClientConfirmed) { $CloseoutArgs += "-ClientConfirmed" }
  if ($RunClientCheck) { $CloseoutArgs += "-RunClientCheck" }
  return Run-Step "installation-closeout" { powershell @CloseoutArgs } -AllowFailure
}

function Wait-Or-Return {
  param(
    [string]$Code,
    [string]$Command,
    [string]$Message
  )
  Save-State "waiting_manual" "manual_intervention" $Code $Command
  Write-Host ""
  Write-Host "bootstrap_state=waiting_manual"
  Write-Host "next_action_code=$Code"
  Write-Host "next_action_command=$Command"
  Write-Host "session_dir=$SessionDir"
  Write-Host "log_path=$MainLog"
  Write-Host $Message
  Write-FlowLog "WAIT" "next_action_code=$Code command=$Command"
  if ($NoPause) { return $false }
  Read-Host "Complete the manual step, then press Enter to re-check"
  return $true
}

function Write-PrerequisiteHelp {
  param([string]$Reason, [string]$Evidence)
  Save-State "waiting_prerequisite" "preflight" $Reason "manual_prerequisite_setup"
  Write-Host ""
  Write-Host "bootstrap_state=waiting_prerequisite"
  Write-Host "next_action_code=$Reason"
  Write-Host "session_dir=$SessionDir"
  Write-Host "log_path=$MainLog"
  if ($Evidence) { Write-Host $Evidence.Trim() }
  Write-Host ""
  Write-Host "Manual prerequisite setup:"
  Write-Host "- Windows: enable/install OpenSSH Client; ensure tar.exe is available; rerun from Windows PowerShell 5.1 or newer. Optional: install Git for easier checkout management."
  Write-Host "- macOS: run xcode-select --install if ssh/tar/gzip/base64/sed/awk/grep/date/mktemp are missing; Homebrew is optional."
  Write-Host "- Linux: install openssh-client, tar, gzip, coreutils, sed, awk, grep, and ca-certificates with your distribution package manager."
  Write-Host "- Router: enable LAN SSH and JFFS custom scripts/configs in the ASUS/Asuswrt-Merlin Web GUI; confirm the LAN IP and SSH user."
  Write-FlowLog "WAIT" "prerequisite_block=$Reason"
}

function Invoke-Preflight {
  if ($env:BOOTSTRAP_TEST_MODE -eq "1") {
    Write-FlowLog "INFO" "preflight_skipped_test_mode=1"
    return $true
  }
  $NoWall = Run-Step "preflight-no-wall" {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "check-no-wall-readiness.ps1") -Repo $Repo
  } -AllowFailure
  if ($NoWall.ExitCode -ne 0) {
    Write-PrerequisiteHelp "missing_local_tools" $NoWall.Output
    return $false
  }

  $HostSsh = Run-Step "preflight-host-ssh" {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "check-host-ssh.ps1") -Router $Router -KnownHostsFile $KnownHostsFile
  } -AllowFailure
  $HostState = Get-StateValue $HostSsh.Output "host_ssh_check_state"
  if ($HostState -ne "ready") {
    $Hint = Get-StateValue $HostSsh.Output "ssh_failure_hint"
    if (-not $Hint) { $Hint = $HostState }
    Write-PrerequisiteHelp $Hint $HostSsh.Output
    return $false
  }
  return $true
}
function Cleanup-Scratch {
  if ((Test-Path -LiteralPath $ScratchDir -PathType Container) -and (Test-Path -LiteralPath $ScratchMarker -PathType Leaf)) {
    Remove-Item -LiteralPath $ScratchDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-FlowLog "INFO" "cleanup=scratch_removed"
    return
  }
  if (Test-Path -LiteralPath $ScratchDir) {
    Write-FlowLog "WARN" "cleanup=skipped_unowned_scratch path=$ScratchDir"
  }
}
function Acquire-BootstrapLock {
  if (Test-Path -LiteralPath $LockDir) {
    $Owner = $null
    try {
      $Owner = Get-Content -LiteralPath (Join-Path $LockDir "owner.json") -Raw | ConvertFrom-Json
    }
    catch {
      $Owner = $null
    }

    $OwnerAlive = $false
    if ($Owner -and $Owner.pid) {
      try {
        $OwnerProcess = Get-Process -Id ([int]$Owner.pid) -ErrorAction Stop
        $OwnerStart = $OwnerProcess.StartTime.ToUniversalTime().ToString("o")
        $OwnerAlive = ($OwnerStart -eq [string]$Owner.process_start_utc)
      }
      catch {
        $OwnerAlive = $false
      }
    }

    if ($OwnerAlive) {
      Write-Host "bootstrap_state=busy"
      Write-Host "lock_owner_pid=$($Owner.pid)"
      Write-Host "session_dir=$SessionDir"
      exit 75
    }
    Remove-Item -LiteralPath $LockDir -Recurse -Force
  }

  try {
    New-Item -ItemType Directory -Path $LockDir -ErrorAction Stop | Out-Null
  }
  catch {
    Write-Host "bootstrap_state=busy"
    Write-Host "session_dir=$SessionDir"
    exit 75
  }

  $OwnerPath = Join-Path $LockDir "owner.json"
  $OwnerTempPath = "$OwnerPath.tmp"
  [ordered]@{
    pid = $PID
    process_start_utc = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString("o")
    started_at = (Now-Iso)
  } | ConvertTo-Json | Set-Content -LiteralPath $OwnerTempPath -Encoding UTF8
  Move-Item -LiteralPath $OwnerTempPath -Destination $OwnerPath -Force
  $script:LockHeld = $true
}

function Release-BootstrapLock {
  if ($script:LockHeld -and (Test-Path -LiteralPath $LockDir)) {
    Remove-Item -LiteralPath $LockDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  $script:LockHeld = $false
}

Acquire-BootstrapLock
try {

Save-State "running" "start"
Write-FlowLog "INFO" "bootstrap_start router=$Router session_dir=$SessionDir"
if (-not (Invoke-Preflight)) { exit 0 }

for ($Loop = 1; $Loop -le $MaxLoops; $Loop++) {
  Save-State "running" "guide"
  Write-FlowLog "INFO" "loop=$Loop"
  $Guide = Invoke-Guide
  $Code = [string]$Guide.next_action_code
  $Command = [string]$Guide.next_action_command
  if (-not $Code) { $Code = "inspect_audit_log" }
  if (-not $Command) { $Command = ".\scripts\guide-router.ps1 -Router $Router -NoPause" }
  Write-FlowLog "INFO" "guide_next_action=$Code"

  switch ($Code) {
    "enable_router_prereqs" {
      if (-not (Wait-Or-Return $Code $Command "Enable LAN SSH and JFFS custom scripts/configs in the router Web UI, then continue.")) { exit 0 }
      continue
    }
    "resolve_action_findings" {
      if (-not (Wait-Or-Return $Code $Command "Resolve ACTION findings from the audit, then continue.")) { exit 0 }
      continue
    }
    "review_baseline_findings" {
      if (-not (Wait-Or-Return $Code $Command "Review and accept or correct REVIEW findings, then continue.")) { exit 0 }
      continue
    }
    "deploy_plan" {
      if ($ApplyDeploy) {
        Run-Step "deploy-apply" { powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "deploy-merlin.ps1") -Router $Router -KnownHostsFile $KnownHostsFile -Apply } | Out-Null
        continue
      }
      Write-FlowLog "INFO" "deploy_ready apply_required=1"
      if (-not (Wait-Or-Return $Code ".\scripts\run-bootstrap.ps1 -Router $Router -ApplyDeploy" "Deployment is ready. Rerun with -ApplyDeploy after reviewing the guide output, or deploy manually and continue.")) { exit 0 }
      continue
    }
    "store_or_import_subscription" {
      if (-not (Wait-Or-Return $Code $Command "Store the provider subscription with store-subscription, or import/start it in ShellCrash, then continue.")) { exit 0 }
      continue
    }
    "store_subscription_for_managed_switching" {
      if (-not (Wait-Or-Return $Code $Command "The live route works, but project-managed provider switching needs the subscription stored on the router.")) { exit 0 }
      continue
    }
    "inspect_self_heal_dry_run" {
      Run-Step "router-status" { powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "check-router-status.ps1") -Router $Router -LogPath $RouterStatusLog -KnownHostsFile $KnownHostsFile -NoPause } -AllowFailure | Out-Null
      if (-not (Wait-Or-Return $Code ".\scripts\check-router-status.ps1 -Router $Router -NoPause" "Inspect the DRY-RUN self-heal log. Continue after the route is healthy.")) { exit 0 }
      continue
    }
    "repair_self_heal_registration" {
      if (-not (Wait-Or-Return $Code $Command "Restore the project-owned boot hook and self-heal scheduler, then continue.")) { exit 0 }
      continue
    }
    "enable_live_self_heal" {
      if ($EnableLiveSelfHeal) {
        Run-Step "enable-live-self-heal" { powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "enable-live-self-heal.ps1") -Router $Router -KnownHostsFile $KnownHostsFile -NoPause } | Out-Null
        continue
      }
      if (-not (Wait-Or-Return $Code ".\scripts\run-bootstrap.ps1 -Router $Router -EnableLiveSelfHeal" "The route is verified in DRY-RUN. Rerun with -EnableLiveSelfHeal when you are ready for real automatic switching.")) { exit 0 }
      continue
    }
    "monitor_live_managed" {
      $Closeout = Invoke-Closeout
      $CloseoutState = Get-StateValue $Closeout.Output "installation_closeout_state"
      $Next = Get-StateValue $Closeout.Output "next_action"
      if ($CloseoutState -eq "pass") {
        Cleanup-Scratch
        Save-State "pass" "complete" "none" "none"
        Write-Host ""
        Write-Host "bootstrap_state=pass"
        Write-Host "installation_closeout_state=pass"
        Write-Host "session_dir=$SessionDir"
        Write-Host "log_path=$MainLog"
        Write-FlowLog "INFO" "bootstrap_complete"
        exit 0
      }
      if ($CloseoutState -eq "accepted_boundary") {
        Cleanup-Scratch
        Save-State "accepted_boundary" "accepted_boundary" "none" "none"
        Write-Host ""
        Write-Host "bootstrap_state=accepted_boundary"
        Write-Host "installation_closeout_state=accepted_boundary"
        Write-Host "session_dir=$SessionDir"
        Write-Host "log_path=$MainLog"
        Write-FlowLog "INFO" "bootstrap_accepted_boundary"
        exit 0
      }
      if (-not $Next) { $Next = "Inspect installation closeout log, then continue." }
      if (-not (Wait-Or-Return "installation_closeout_$CloseoutState" $Command $Next)) { exit 0 }
      continue
    }
    default {
      if (-not (Wait-Or-Return $Code $Command "State is incomplete or unknown. Inspect the session logs, then continue.")) { exit 0 }
      continue
    }
  }
}

Save-State "failed" "max_loops_exceeded"
Write-FlowLog "ERROR" "max_loops_exceeded=$MaxLoops"
throw "Bootstrap did not converge within $MaxLoops loops. See $MainLog"}
catch {
  $CurrentState = ""
  try {
    if (Test-Path -LiteralPath $StatePath) {
      $CurrentState = [string](Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json).bootstrap_state
    }
  }
  catch {}
  if ($CurrentState -ne "failed") {
    Save-State "failed" "unhandled_exception" "inspect_logs" $MainLog
  }
  Write-FlowLog "ERROR" "bootstrap_unhandled_error=$($_.Exception.Message)"
  throw
}
finally {
  Release-BootstrapLock
}
